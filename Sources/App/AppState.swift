import Foundation
import Observation

@Observable
@MainActor
final class AppState {
    static let shared = AppState()

    var instances: [Instance] = []
    var selectedInstance: Instance?
    var showAllHubs = false
    var systemsByHub: [UUID: [SystemRecord]] = [:]
    var systemDetails: [UUID: [String: SystemDetailsRecord]] = [:]
    var containers: [UUID: [String: [ContainerRecord]]] = [:]
    var alertsByHub: [UUID: [AlertRecord]] = [:]
    var hubErrors: [UUID: String] = [:]
    var isLoading = false
    var isConfigured = false

    private let storage = StorageManager()
    private let keychain = KeychainService.shared
    private var apiServices: [UUID: BeszelAPIService] = [:]
    private var loadTask: Task<Void, Never>?
    private var detailsTask: Task<Void, Never>?
    private var alertTask: Task<Void, Never>?
    private var containerTask: Task<Void, Never>?

    private init() {
        loadInstances()
        isConfigured = !instances.isEmpty
        if !visibleHubs.isEmpty {
            reloadAll()
        }
    }

    /// Hubs whose systems are currently shown in the menu.
    var visibleHubs: [Instance] {
        if showAllHubs {
            return instances
        }
        guard let selected = selectedInstance else { return [] }
        return [selected]
    }

    var isShowingMultipleHubs: Bool {
        visibleHubs.count > 1
    }

    var visibleSystems: [SystemRecord] {
        visibleHubs.flatMap { systems(for: $0) }
    }

    var activeAlerts: [HubAlert] {
        visibleHubs.flatMap { hub in
            (alertsByHub[hub.id] ?? []).map { HubAlert(hub: hub, alert: $0) }
        }
    }

    func systems(for hub: Instance) -> [SystemRecord] {
        systemsByHub[hub.id] ?? []
    }

    func reloadAll() {
        loadSystems()
        loadSystemDetails()
        loadAlerts()
        loadContainers()
    }

    func loadSystems() {
        let hubs = visibleHubs
        guard !hubs.isEmpty else { return }

        loadTask?.cancel()
        loadTask = Task {
            isLoading = true

            defer { isLoading = false }

            let results = await fetchFromHubs(hubs) { try await $0.fetchSystems() }
            guard !Task.isCancelled else { return }

            var updatedSystems = systemsByHub
            var updatedErrors = hubErrors
            for (hubID, result) in results {
                switch result {
                case .success(let systems):
                    updatedSystems[hubID] = systems.sorted { $0.name < $1.name }
                    updatedErrors[hubID] = nil
                case .failure(let error):
                    if error is CancellationError { continue }
                    updatedErrors[hubID] = error.localizedDescription
                }
            }
            systemsByHub = updatedSystems
            hubErrors = updatedErrors
        }
    }

    func loadSystemDetails() {
        let hubs = visibleHubs
        guard !hubs.isEmpty else { return }

        detailsTask?.cancel()
        detailsTask = Task {
            let results = await fetchFromHubs(hubs) { try await $0.fetchSystemDetails() }
            guard !Task.isCancelled else { return }

            var updated = systemDetails
            for (hubID, result) in results {
                guard case .success(let details) = result else { continue }

                var mapped: [String: SystemDetailsRecord] = [:]
                for detail in details {
                    mapped[detail.system] = detail
                }
                updated[hubID] = mapped
            }
            systemDetails = updated
        }
    }

    func loadAlerts() {
        let hubs = visibleHubs
        guard !hubs.isEmpty else { return }

        alertTask?.cancel()
        alertTask = Task {
            let results = await fetchFromHubs(hubs) { try await $0.fetchAlerts(filter: "enabled = true") }
            guard !Task.isCancelled else { return }

            var updated = alertsByHub
            for (hubID, result) in results {
                guard case .success(let alerts) = result else { continue }
                updated[hubID] = alerts.filter { $0.triggered == true }
            }
            alertsByHub = updated
        }
    }

    func loadContainers() {
        let hubs = visibleHubs
        guard !hubs.isEmpty else { return }

        containerTask?.cancel()
        containerTask = Task {
            let results = await fetchFromHubs(hubs) { try await $0.fetchContainers() }
            guard !Task.isCancelled else { return }

            var updated = containers
            for (hubID, result) in results {
                guard case .success(let allContainers) = result else { continue }

                var grouped: [String: [ContainerRecord]] = [:]
                for container in allContainers {
                    grouped[container.system, default: []].append(container)
                }
                updated[hubID] = grouped
            }
            containers = updated
        }
    }

    func selectInstance(_ instance: Instance?) {
        selectedInstance = instance
        showAllHubs = false
        clearHubData()
        reloadAll()
        storage.saveSelectedInstanceID(instance?.id)
        storage.saveShowAllHubs(false)
    }

    func selectAllHubs() {
        showAllHubs = true
        clearHubData()
        reloadAll()
        storage.saveShowAllHubs(true)
    }

    func addInstance(_ instance: Instance) {
        keychain.saveCredential(instance.credential, for: instance.id.uuidString)

        var storedInstance = instance
        storedInstance.credential = ""
        instances.append(storedInstance)
        saveInstances()

        if selectedInstance == nil {
            selectInstance(storedInstance)
        } else if showAllHubs {
            reloadAll()
        }
        isConfigured = true
    }

    func removeInstance(_ instance: Instance) {
        keychain.deleteCredential(for: instance.id.uuidString)
        apiServices.removeValue(forKey: instance.id)
        instances.removeAll { $0.id == instance.id }
        saveInstances()
        clearHubData(for: instance.id)

        if selectedInstance?.id == instance.id {
            selectedInstance = instances.first
            storage.saveSelectedInstanceID(selectedInstance?.id)
            if !showAllHubs {
                clearHubData()
                reloadAll()
            }
        }
        isConfigured = !instances.isEmpty
    }

    func updateInstance(_ instance: Instance) {
        if !instance.credential.isEmpty {
            keychain.updateCredential(instance.credential, for: instance.id.uuidString)
        }

        apiServices.removeValue(forKey: instance.id)

        var storedInstance = instance
        storedInstance.credential = ""

        if let index = instances.firstIndex(where: { $0.id == instance.id }) {
            instances[index] = storedInstance
            saveInstances()
        }

        if selectedInstance?.id == instance.id {
            selectedInstance = storedInstance
        }

        if visibleHubs.contains(where: { $0.id == instance.id }) {
            clearHubData(for: instance.id)
            reloadAll()
        }
    }

    func instanceWithCredential(_ instance: Instance) -> Instance {
        var fullInstance = instance
        fullInstance.credential = keychain.loadCredential(for: instance.id.uuidString) ?? ""
        return fullInstance
    }

    private func clearHubData() {
        systemsByHub = [:]
        systemDetails = [:]
        containers = [:]
        alertsByHub = [:]
        hubErrors = [:]
    }

    private func clearHubData(for hubID: UUID) {
        systemsByHub[hubID] = nil
        systemDetails[hubID] = nil
        containers[hubID] = nil
        alertsByHub[hubID] = nil
        hubErrors[hubID] = nil
    }

    /// Runs `fetch` against every hub concurrently and collects a result per hub,
    /// so one unreachable hub doesn't prevent the others from loading.
    private func fetchFromHubs<T: Sendable>(
        _ hubs: [Instance],
        _ fetch: @escaping @Sendable (BeszelAPIService) async throws -> T
    ) async -> [UUID: Result<T, Error>] {
        let services = hubs.map { ($0.id, getOrCreateService(for: $0)) }

        return await withTaskGroup(of: (UUID, Result<T, Error>).self) { group in
            for (hubID, service) in services {
                group.addTask {
                    do {
                        let value = try await fetch(service)
                        return (hubID, .success(value))
                    } catch {
                        return (hubID, .failure(error))
                    }
                }
            }

            var results: [UUID: Result<T, Error>] = [:]
            for await (hubID, result) in group {
                results[hubID] = result
            }
            return results
        }
    }

    private func loadInstances() {
        instances = storage.loadInstances()

        if let savedID = storage.loadSelectedInstanceID(),
           let instance = instances.first(where: { $0.id == savedID }) {
            selectedInstance = instance
        } else {
            selectedInstance = instances.first
        }

        showAllHubs = storage.loadShowAllHubs()
    }

    private func saveInstances() {
        storage.saveInstances(instances)
    }

    private func getOrCreateService(for instance: Instance) -> BeszelAPIService {
        if let existing = apiServices[instance.id] {
            return existing
        }

        let fullInstance = instanceWithCredential(instance)
        let service = BeszelAPIService(instance: fullInstance)
        apiServices[instance.id] = service
        return service
    }
}

struct HubAlert: Identifiable {
    let hub: Instance
    let alert: AlertRecord

    var id: String { "\(hub.id.uuidString)-\(alert.id)" }
}


struct Instance: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var name: String
    var url: String
    var email: String
    var credential: String

    init(id: UUID = UUID(), name: String, url: String, email: String, credential: String) {
        self.id = id
        self.name = name
        self.url = url
        self.email = email
        self.credential = credential
    }

    var displayName: String {
        name.isEmpty ? url : name
    }

    enum CodingKeys: String, CodingKey {
        case id, name, url, email
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        url = try container.decode(String.self, forKey: .url)
        email = try container.decode(String.self, forKey: .email)
        credential = ""
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(url, forKey: .url)
        try container.encode(email, forKey: .email)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: Instance, rhs: Instance) -> Bool {
        lhs.id == rhs.id
    }
}

final class StorageManager {
    private let defaults = UserDefaults.standard
    private let instancesKey = "com.nohitdev.BeszelBar.instances"
    private let selectedInstanceKey = "com.nohitdev.BeszelBar.selectedInstance"
    private let showAllHubsKey = "com.nohitdev.BeszelBar.showAllHubs"

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

    func saveShowAllHubs(_ showAll: Bool) {
        defaults.set(showAll, forKey: showAllHubsKey)
    }

    func loadShowAllHubs() -> Bool {
        defaults.bool(forKey: showAllHubsKey)
    }
}
