import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    static let shared: AppState = {
        #if DEBUG
        if let state = DevelopmentSession.makeState() { return state }
        #endif
        return AppState()
    }()

    private(set) var instances: [Instance] = []
    private(set) var selectedInstance: Instance?
    private(set) var showsAllHubs: Bool
    private(set) var hubSnapshots: [UUID: HubSnapshot] = [:]
    private(set) var connectionRevision = 0

    private let storage: StorageManager
    private let credentials: any CredentialStore
    private let serviceFactory: (Instance) -> any BeszelServing
    @ObservationIgnored private var apiServices: [UUID: any BeszelServing] = [:]
    @ObservationIgnored private var refreshTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var generations: [UUID: UUID] = [:]

    init(storage: StorageManager = StorageManager(),
         credentials: any CredentialStore = KeychainService.shared,
         serviceFactory: @escaping (Instance) -> any BeszelServing = { BeszelAPIService(instance: $0) }) {
        self.storage = storage
        self.credentials = credentials
        self.serviceFactory = serviceFactory
        showsAllHubs = storage.loadShowsAllHubs()
        instances = storage.loadInstances()
        selectedInstance = instances.first { $0.id == storage.loadSelectedInstanceID() } ?? instances.first
    }

    var visibleInstances: [Instance] {
        showsAllHubs ? instances : selectedInstance.map { [$0] } ?? []
    }
    var scopeTitle: String { showsAllHubs ? "All Hubs" : selectedInstance?.displayName ?? "No Hub Configured" }
    var isLoading: Bool { visibleInstances.contains { hubSnapshots[$0.id]?.isLoading == true } }
    var isConfigured: Bool { !instances.isEmpty }
    var visibleSystems: [HubSystem] {
        visibleInstances.flatMap { instance in
            (hubSnapshots[instance.id]?.systems ?? []).map { HubSystem(instance: instance, system: $0, connectionURL: hubSnapshots[instance.id]?.connectedURL) }
        }
    }
    var visibleAlerts: [HubAlert] {
        visibleInstances.flatMap { instance in
            let snapshot = hubSnapshots[instance.id] ?? HubSnapshot()
            return snapshot.alerts.map { alert in
                HubAlert(instance: instance, alert: alert,
                         systemName: snapshot.systems.first { $0.id == alert.system }?.name ?? alert.system ?? "Unknown system")
            }
        }
    }
    var visibleContainers: [HubContainer] {
        visibleInstances.flatMap { instance in
            let snapshot = hubSnapshots[instance.id] ?? HubSnapshot()
            return snapshot.containers.map { container in
                HubContainer(instance: instance, container: container,
                             systemName: snapshot.systems.first { $0.id == container.system }?.name ?? container.system)
            }
        }
    }
    var activeAlerts: [HubAlert] { visibleAlerts.filter { $0.alert.triggered == true } }

    func system(for id: HubRecordID) -> HubSystem? {
        guard let instance = instances.first(where: { $0.id == id.hubID }),
              let system = hubSnapshots[id.hubID]?.systems.first(where: { $0.id == id.recordID }) else { return nil }
        return HubSystem(instance: instance, system: system, connectionURL: hubSnapshots[instance.id]?.connectedURL)
    }

    func refresh() {
        for instance in visibleInstances { refresh(instance) }
    }

    func refresh(_ instance: Instance) {
        guard refreshTasks[instance.id] == nil,
              instances.contains(where: { $0.id == instance.id }) else { return }
        let generation = UUID()
        generations[instance.id] = generation
        hubSnapshots[instance.id, default: HubSnapshot()].isLoading = true
        let service = getOrCreateService(for: instance)
        refreshTasks[instance.id] = Task { [weak self] in
            guard let self else { return }
            defer {
                if self.generations[instance.id] == generation {
                    self.hubSnapshots[instance.id]?.isLoading = false
                    self.refreshTasks[instance.id] = nil
                }
            }
            do {
                let systems = try await service.fetchSystems()
                let endpoint = await service.currentEndpoint()
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id, default: HubSnapshot()].systems = systems.sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                self.hubSnapshots[instance.id]?.connectedURL = endpoint
                self.hubSnapshots[instance.id]?.errorMessage = nil
                self.hubSnapshots[instance.id]?.resourceErrors = []
                self.hubSnapshots[instance.id]?.lastUpdated = Date()
            } catch {
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.errorMessage = error.localizedDescription
                return
            }

            // Each hub progresses independently. Optional collections can fail without hiding systems.
            do {
                let details = try await service.fetchSystemDetails()
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.details = Dictionary(details.map { ($0.system, $0) }, uniquingKeysWith: { _, new in new })
            } catch {
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.resourceErrors.append("System details: \(error.localizedDescription)")
            }
            do {
                let containers = try await service.fetchContainers(filter: nil)
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.containers = containers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            } catch {
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.resourceErrors.append("Containers: \(error.localizedDescription)")
            }
            do {
                let alerts = try await service.fetchAlerts(filter: nil)
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.alerts = alerts.filter { $0.enabled != false }
            } catch {
                guard self.accepts(instance.id, generation: generation) else { return }
                self.hubSnapshots[instance.id]?.resourceErrors.append("Alerts: \(error.localizedDescription)")
            }
        }
    }

    func waitForRefresh() async {
        for task in Array(refreshTasks.values) { await task.value }
    }

    func stopRefreshing() {
        for id in Array(refreshTasks.keys) { cancelRefresh(for: id) }
    }

    private func accepts(_ id: UUID, generation: UUID) -> Bool {
        !Task.isCancelled && generations[id] == generation && instances.contains { $0.id == id }
    }

    private func cancelRefresh(for id: UUID) {
        generations[id] = nil
        refreshTasks.removeValue(forKey: id)?.cancel()
        hubSnapshots[id]?.isLoading = false
    }

    func selectInstance(_ instance: Instance?) {
        if let instance, !instances.contains(where: { $0.id == instance.id }) { return }
        showsAllHubs = instance == nil
        if let instance { selectedInstance = instances.first { $0.id == instance.id } }
        storage.saveShowsAllHubs(showsAllHubs)
        storage.saveSelectedInstanceID(selectedInstance?.id)
        let visibleIDs = Set(visibleInstances.map(\.id))
        for id in Array(refreshTasks.keys) where !visibleIDs.contains(id) { cancelRefresh(for: id) }
        refresh()
    }

    func addInstance(_ instance: Instance) {
        credentials.saveCredential(instance.credential, for: instance.id.uuidString)
        var stored = instance
        stored.credential = ""
        instances.append(stored)
        if selectedInstance == nil { selectedInstance = stored }
        saveInstances()
        refresh()
    }

    func removeInstance(_ instance: Instance) {
        cancelRefresh(for: instance.id)
        credentials.deleteCredential(for: instance.id.uuidString)
        apiServices[instance.id] = nil
        hubSnapshots[instance.id] = nil
        instances.removeAll { $0.id == instance.id }
        if selectedInstance?.id == instance.id { selectedInstance = instances.first }
        connectionRevision += 1
        saveInstances()
        refresh()
    }

    func updateInstance(_ instance: Instance) {
        guard let index = instances.firstIndex(where: { $0.id == instance.id }) else { return }
        if !instance.credential.isEmpty {
            credentials.saveCredential(instance.credential, for: instance.id.uuidString)
        }
        cancelRefresh(for: instance.id)
        apiServices[instance.id] = nil
        hubSnapshots[instance.id] = nil
        var stored = instance
        stored.credential = ""
        instances[index] = stored
        if selectedInstance?.id == instance.id { selectedInstance = stored }
        connectionRevision += 1
        saveInstances()
        refresh()
    }

    func instanceWithCredential(_ instance: Instance) -> Instance {
        var result = instance
        result.credential = credentials.loadCredential(for: instance.id.uuidString) ?? ""
        return result
    }

    func fetchHistory(for id: HubRecordID, range: HistoryRange, now: Date = Date()) async throws -> [SystemStatsRecord] {
        guard let instance = instances.first(where: { $0.id == id.hubID }) else { throw CancellationError() }
        return try await getOrCreateService(for: instance).fetchHistory(systemID: id.recordID, range: range, now: now)
    }

    func chartService(for id: HubRecordID) throws -> any BeszelServing {
        guard let instance = instances.first(where: { $0.id == id.hubID }) else { throw CancellationError() }
        return getOrCreateService(for: instance)
    }

    private func saveInstances() {
        storage.saveInstances(instances)
        storage.saveSelectedInstanceID(selectedInstance?.id)
    }

    private func getOrCreateService(for instance: Instance) -> any BeszelServing {
        if let service = apiServices[instance.id] { return service }
        let service = serviceFactory(instanceWithCredential(instance))
        apiServices[instance.id] = service
        return service
    }
}

struct Instance: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var email: String
    var credential: String
    var fallbackURL: String

    init(id: UUID = UUID(), name: String, url: String, email: String, credential: String, fallbackURL: String = "") {
        self.id = id
        self.name = name
        self.url = url
        self.email = email
        self.credential = credential
        self.fallbackURL = fallbackURL
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, email, fallbackURL
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        email = try container.decode(String.self, forKey: .email)
        credential = ""
        fallbackURL = try container.decodeIfPresent(String.self, forKey: .fallbackURL) ?? ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(email, forKey: .email)
        if !fallbackURL.isEmpty { try container.encode(fallbackURL, forKey: .fallbackURL) }
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Instance, rhs: Instance) -> Bool {
        lhs.id == rhs.id
    }
}

final class StorageManager {
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func loadShowsAllHubs() -> Bool { defaults.bool(forKey: "com.nohitdev.BeszelBar.allHubs") }
    func saveShowsAllHubs(_ value: Bool) { defaults.set(value, forKey: "com.nohitdev.BeszelBar.allHubs") }
    private let instancesKey = "com.nohitdev.BeszelBar.instances"
    private let selectedInstanceKey = "com.nohitdev.BeszelBar.selectedInstance"

    func saveInstances(_ instances: [Instance]) {
        guard let data = try? JSONEncoder().encode(instances) else { return }
        defaults.set(data, forKey: instancesKey)
    }

    func loadInstances() -> [Instance] {
        guard let data = defaults.data(forKey: instancesKey),
              let instances = try? JSONDecoder().decode([Instance].self, from: data) else {
            return []
        }
        return instances
    }

    func saveSelectedInstanceID(_ id: UUID?) {
        if let id = id {
            defaults.set(id.uuidString, forKey: selectedInstanceKey)
        } else {
            defaults.removeObject(forKey: selectedInstanceKey)
        }
    }

    func loadSelectedInstanceID() -> UUID? {
        guard let string = defaults.string(forKey: selectedInstanceKey) else { return nil }
        return UUID(uuidString: string)
    }
}
