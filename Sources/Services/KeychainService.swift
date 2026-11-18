import Foundation
import Security

protocol CredentialStore {
    @discardableResult func saveCredential(_ credential: String, for account: String) -> Bool
    func loadCredential(for account: String) -> String?
    @discardableResult func deleteCredential(for account: String) -> Bool
}

protocol KeychainClient {
    func read(_ query: [String: Any]) -> (OSStatus, Data?)
    func add(_ attributes: [String: Any]) -> OSStatus
    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus
    func delete(_ query: [String: Any]) -> OSStatus
}

struct SystemKeychainClient: KeychainClient {
    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        return (status, result as? Data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        SecItemAdd(attributes as CFDictionary, nil)
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        SecItemDelete(query as CFDictionary)
    }
}

final class KeychainService: CredentialStore {
    static let shared = KeychainService()

    private struct Vault: Codable {
        var version = 1
        var credentials: [String: String] = [:]
        // Tombstones prevent a legacy entry whose cleanup failed from returning.
        var migratedAccounts: Set<String> = []
    }

    private let service = "com.nohitdev.BeszelBar"
    private let vaultAccount = "hub-credentials-v1"
    private let keychain: any KeychainClient
    private let lock = NSLock()
    private var cachedVault: Vault?

    init(keychain: any KeychainClient = SystemKeychainClient()) { self.keychain = keychain }

    @discardableResult
    func saveCredential(_ credential: String, for account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard account != vaultAccount, var vault = readVault(refresh: true) else { return false }
        vault.credentials[account] = credential
        vault.migratedAccounts.insert(account)
        guard persist(vault) else { return false }
        removeLegacyCredential(for: account)
        return true
    }

    func loadCredential(for account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        guard account != vaultAccount, let vault = readVault() else { return nil }
        if let credential = vault.credentials[account] { return credential }
        guard !vault.migratedAccounts.contains(account) else { return nil }

        // Existing per-hub entries still need their own authorization once.
        let (status, data) = keychain.read(readQuery(for: account))
        guard status == errSecSuccess,
              let data, let credential = String(data: data, encoding: .utf8) else { return nil }

        // Keep the original entry if the shared vault cannot be saved.
        if var latest = readVault(refresh: true) {
            if latest.migratedAccounts.contains(account) { return latest.credentials[account] }
            latest.credentials[account] = credential
            latest.migratedAccounts.insert(account)
            if persist(latest) { removeLegacyCredential(for: account) }
        }
        return credential
    }

    @discardableResult
    func deleteCredential(for account: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard account != vaultAccount, var vault = readVault(refresh: true) else { return false }
        vault.credentials.removeValue(forKey: account)
        vault.migratedAccounts.insert(account)
        // Keep even an empty vault so its access permissions survive hub removal.
        guard persist(vault) else { return false }
        removeLegacyCredential(for: account)
        return true
    }

    @discardableResult
    func updateCredential(_ credential: String, for account: String) -> Bool {
        saveCredential(credential, for: account)
    }

    func hasCredential(for account: String) -> Bool {
        loadCredential(for: account) != nil
    }

    private func query(for account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    private func readQuery(for account: String) -> [String: Any] {
        var query = query(for: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        return query
    }

    private func readVault(refresh: Bool = false) -> Vault? {
        if !refresh, let cachedVault { return cachedVault }
        let (status, data) = keychain.read(readQuery(for: vaultAccount))
        if status == errSecItemNotFound {
            let vault = Vault()
            cachedVault = vault
            return vault
        }
        // A refusal, a locked keychain or unreadable data must never be treated
        // as an empty vault: writing it would discard the other hubs' secrets.
        guard status == errSecSuccess, let data,
              let vault = try? JSONDecoder().decode(Vault.self, from: data),
              vault.version == 1 else { return nil }
        cachedVault = vault
        return vault
    }

    private func persist(_ vault: Vault) -> Bool {
        guard let data = try? JSONEncoder().encode(vault) else { return false }
        let query = query(for: vaultAccount)
        let status = keychain.update(query, attributes: [kSecValueData as String: data])
        if status == errSecItemNotFound {
            var attributes = query
            attributes[kSecValueData as String] = data
            attributes[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            attributes[kSecAttrLabel as String] = "BeszelBar"
            guard keychain.add(attributes) == errSecSuccess else { return false }
        } else if status != errSecSuccess {
            return false
        }
        cachedVault = vault
        return true
    }

    private func removeLegacyCredential(for account: String) {
        // The vault is already durable; a refused cleanup must not undo it.
        _ = keychain.delete(query(for: account))
    }
}
