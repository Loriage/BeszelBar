#if DEBUG
import Foundation

/// Opt-in local UI testing. TestingHubs.json is supplied only to the built Debug
/// bundle, never to source control or release builds. No real preferences or
/// Keychain entries are read or changed by this session.
@MainActor
enum DevelopmentSession {
    static var isTestHost: Bool { ProcessInfo.processInfo.environment["BESZELBAR_TEST_HOST"] == "1" }

    static var isEnabled: Bool { Bundle.main.url(forResource: "TestingHubs", withExtension: "json") != nil }

    private struct Configuration: Decodable {
        let hubs: [Hub]
        let allHubs: Bool
        struct Hub: Decodable {
            let name: String
            let url: String
            let email: String
            let password: String
            let fallbackURL: String?
        }
    }

    static func makeState() -> AppState? {
        if isTestHost {
            let defaults = UserDefaults(suiteName: "com.nohitdev.BeszelBar.test-host")!
            defaults.removePersistentDomain(forName: "com.nohitdev.BeszelBar.test-host")
            return AppState(storage: StorageManager(defaults: defaults), credentials: MemoryCredentials())
        }
        guard let file = Bundle.main.url(forResource: "TestingHubs", withExtension: "json") else { return nil }
        let suite = "com.nohitdev.BeszelBar.testing"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let storage = StorageManager(defaults: defaults)
        let credentials = MemoryCredentials()
        let state = AppState(storage: storage, credentials: credentials)
        guard let data = try? Data(contentsOf: file),
              let configuration = try? JSONDecoder().decode(Configuration.self, from: data) else { return state }
        for hub in configuration.hubs {
            state.addInstance(Instance(name: hub.name, url: hub.url, email: hub.email, credential: hub.password, fallbackURL: hub.fallbackURL ?? ""))
        }
        if configuration.allHubs { state.selectInstance(nil) }
        return state
    }

    private final class MemoryCredentials: CredentialStore {
        private var values: [String: String] = [:]
        func saveCredential(_ credential: String, for account: String) -> Bool { values[account] = credential; return true }
        func loadCredential(for account: String) -> String? { values[account] }
        func deleteCredential(for account: String) -> Bool { values[account] = nil; return true }
    }
}
#endif
