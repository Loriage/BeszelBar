import XCTest

@MainActor
final class AppStateTests: XCTestCase {
    private var suites: [String] = []

    override func tearDown() {
        for suite in suites { UserDefaults.standard.removePersistentDomain(forName: suite) }
        suites = []
        super.tearDown()
    }

    private func state(_ hubs: [Instance], all: Bool = true,
                       factory: @escaping (Instance) -> any BeszelServing) -> (AppState, StorageManager) {
        let suite = "BeszelBarTests.\(UUID().uuidString)"
        suites.append(suite)
        let storage = StorageManager(defaults: UserDefaults(suiteName: suite)!)
        storage.saveInstances(hubs)
        storage.saveShowsAllHubs(all)
        let state = AppState(storage: storage, credentials: TestCredentials(), serviceFactory: factory)
        return (state, storage)
    }

    func testAllHubsKeepCollidingRecordIDsAndTheirOrigins() async throws {
        let a = hub("A"), b = hub("B")
        let (state, _) = state([a, b]) { TestService(name: $0.name) }
        state.refresh()
        await state.waitForRefresh()
        XCTAssertEqual(state.visibleSystems.count, 2)
        XCTAssertEqual(Set(state.visibleSystems.map(\.id)).count, 2)
        XCTAssertEqual(Set(state.visibleContainers.map(\.id)).count, 2)
        XCTAssertEqual(Set(state.visibleAlerts.map(\.id)).count, 2)
        XCTAssertEqual(state.visibleAlerts.map(\.systemName), ["A server", "B server"])
        XCTAssertEqual(state.visibleContainers.map(\.systemName), ["A server", "B server"])
        XCTAssertEqual(state.hubSnapshots[a.id]?.details["same-system"]?.hostname, "A.local")
        XCTAssertEqual(state.hubSnapshots[b.id]?.details["same-system"]?.hostname, "B.local")
        XCTAssertEqual(state.system(for: HubRecordID(hubID: b.id, recordID: "same-system"))?.browserURL?.host, "b.example")
        XCTAssertFalse(state.isLoading)
    }

    func testUnavailableHubDoesNotHideOtherSystemsAndKeepsLastGoodSnapshot() async {
        let a = hub("A"), b = hub("B")
        let first = TestService(name: "A"), second = TestService(name: "B")
        let (state, _) = state([a, b]) { $0.id == a.id ? first : second }
        state.refresh()
        await state.waitForRefresh()
        await first.setFailure(true)
        state.refresh()
        await state.waitForRefresh()
        XCTAssertNotNil(state.hubSnapshots[a.id]?.errorMessage)
        XCTAssertNotNil(state.hubSnapshots[a.id]?.lastUpdated)
        XCTAssertNil(state.hubSnapshots[b.id]?.errorMessage)
        XCTAssertEqual(state.visibleSystems.count, 2)
        XCTAssertFalse(state.isLoading)
    }

    func testScopePersistsAndRemovingSelectedHubPersistsReplacement() async {
        let a = hub("A"), b = hub("B")
        let (state, storage) = state([a, b]) { TestService(name: $0.name) }
        state.selectInstance(b)
        await state.waitForRefresh()
        XCTAssertEqual(state.visibleSystems.map(\.instance.id), [b.id])
        state.selectInstance(nil)
        await state.waitForRefresh()
        XCTAssertTrue(storage.loadShowsAllHubs())
        let restored = AppState(storage: storage, credentials: TestCredentials(), serviceFactory: { TestService(name: $0.name) })
        XCTAssertTrue(restored.showsAllHubs)
        XCTAssertEqual(restored.visibleInstances.count, 2)
        state.selectInstance(b)
        state.removeInstance(b)
        await state.waitForRefresh()
        XCTAssertEqual(storage.loadSelectedInstanceID(), a.id)
        XCTAssertNil(state.hubSnapshots[b.id])
        XCTAssertEqual(state.visibleInstances.map(\.id), [a.id])
    }

    func testRefreshCoalescesAndSwitchingHubRejectsLateResponses() async {
        let a = hub("A"), b = hub("B")
        let pending = ControlledService()
        let (state, _) = state([a, b], all: false) {
            if $0.id == a.id { return pending }
            return TestService(name: "B")
        }
        state.refresh()
        await pending.waitForStart()
        state.refresh()
        let calls = await pending.calls
        XCTAssertEqual(calls, 1)
        state.selectInstance(b)
        await state.waitForRefresh()
        await pending.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(state.visibleSystems.map(\.system.name), ["B server"])
        XCTAssertTrue(state.hubSnapshots[a.id]?.systems.isEmpty == true)
        XCTAssertFalse(state.isLoading)
    }

    func testEditingHubInvalidatesOldServiceAndLateResults() async {
        let a = hub("A")
        let pending = ControlledService()
        let (state, _) = state([a]) {
            if $0.url.contains("replacement") { return TestService(name: "New") }
            return pending
        }
        state.refresh()
        await pending.waitForStart()
        var edited = a
        edited.url = "https://replacement.example"
        state.updateInstance(edited)
        await state.waitForRefresh()
        await pending.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertEqual(state.visibleSystems.map(\.system.name), ["New server"])
        XCTAssertEqual(state.connectionRevision, 1)
        XCTAssertFalse(state.isLoading)
    }

    func testRemovingLoadingHubDoesNotResurrectIt() async {
        let a = hub("A")
        let pending = ControlledService()
        let (state, _) = state([a]) { _ in pending }
        state.refresh()
        await pending.waitForStart()
        state.removeInstance(a)
        await pending.finish()
        for _ in 0..<20 { await Task.yield() }
        XCTAssertTrue(state.instances.isEmpty)
        XCTAssertTrue(state.hubSnapshots.isEmpty)
        XCTAssertTrue(state.visibleSystems.isEmpty)
        XCTAssertFalse(state.isLoading)
    }

    func testConfiguredAlertsWithoutEnabledOrTriggeredAreVisible() async {
        let a = hub("A")
        let service = TestService(name: "A", triggered: false)
        let (state, _) = state([a]) { _ in service }
        state.refresh()
        await state.waitForRefresh()
        XCTAssertEqual(state.visibleAlerts.count, 1)
        XCTAssertTrue(state.activeAlerts.isEmpty)
        XCTAssertNil(state.hubSnapshots[a.id]?.notice)
        XCTAssertEqual(state.visibleAlerts.first?.alert.displayThreshold, "80")
    }

    func testHistoryUsesOwningHubEvenWithDuplicateSystemIDs() async throws {
        let a = hub("A"), b = hub("B")
        let (state, _) = state([a, b]) { TestService(name: $0.name) }
        let records = try await state.fetchHistory(for: HubRecordID(hubID: b.id, recordID: "same-system"), range: .day)
        XCTAssertEqual(records.first?.id, "B-history")
    }

    private func hub(_ name: String) -> Instance {
        Instance(name: name, url: "https://\(name.lowercased()).example", email: "", credential: "")
    }
}

final class TestCredentials: CredentialStore {
    private var values: [String: String] = [:]
    func saveCredential(_ credential: String, for account: String) -> Bool { values[account] = credential; return true }
    func loadCredential(for account: String) -> String? { values[account] }
    func deleteCredential(for account: String) -> Bool { values[account] = nil; return true }
}

actor TestService: BeszelServing {
    let name: String
    let triggered: Bool
    var fails = false

    init(name: String, triggered: Bool = true) { self.name = name; self.triggered = triggered }
    func setFailure(_ value: Bool) { fails = value }
    func fetchSystems() async throws -> [SystemRecord] {
        if fails { throw URLError(.cannotConnectToHost) }
        return [try fixture(#"{"id":"same-system","name":"\#(name) server","status":"up","info":{"cpu":0,"mp":40,"dp":50}}"#)]
    }
    func fetchSystemDetails() async throws -> [SystemDetailsRecord] {
        [try fixture(#"{"id":"same-details","system":"same-system","hostname":"\#(name).local"}"#)]
    }
    func fetchContainers(filter: String?) async throws -> [ContainerRecord] {
        [try fixture(#"{"id":"same-container","name":"web","cpu":0,"memory":32,"net":0,"health":2,"status":"running","image":"nginx","system":"same-system","updated":0}"#)]
    }
    func fetchAlerts(filter: String?) async throws -> [AlertRecord] {
        // Real Beszel 0.19 has neither an "enabled" filter nor a required triggered field.
        if filter != nil { throw BeszelAPIError.httpError(statusCode: 400, url: "") }
        return [try fixture(#"{"id":"same-alert","name":"CPU","system":"same-system","value":80,"triggered":\#(triggered)}"#)]
    }
    func fetchHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [SystemStatsRecord] {
        [try fixture(#"{"id":"\#(name)-history","created":"2026-09-15 12:00:00.000Z","type":"1m","stats":{"cpu":0}}"#)]
    }
}

/// Deliberately ignores cancellation, like an already completed network callback.
actor ControlledService: BeszelServing {
    private var response: CheckedContinuation<[SystemRecord], Never>?
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var started = false
    private(set) var calls = 0
    func waitForStart() async {
        if started { return }
        await withCheckedContinuation { startWaiter = $0 }
    }
    func fetchSystems() async throws -> [SystemRecord] {
        calls += 1
        started = true
        startWaiter?.resume()
        startWaiter = nil
        return await withCheckedContinuation { response = $0 }
    }
    func finish() {
        let system: SystemRecord = try! fixture(#"{"id":"same-system","name":"Old server","status":"up"}"#)
        response?.resume(returning: [system])
        response = nil
    }
    func fetchSystemDetails() async throws -> [SystemDetailsRecord] { [] }
    func fetchContainers(filter: String?) async throws -> [ContainerRecord] { [] }
    func fetchAlerts(filter: String?) async throws -> [AlertRecord] { [] }
    func fetchHistory(systemID: String, range: HistoryRange, now: Date) async throws -> [SystemStatsRecord] { [] }
}

func fixture<T: Decodable>(_ json: String) throws -> T {
    try JSONDecoder().decode(T.self, from: Data(json.utf8))
}
