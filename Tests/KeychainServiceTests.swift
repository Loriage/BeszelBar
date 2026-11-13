import XCTest
import Security

final class KeychainServiceTests: XCTestCase {
    private let vaultAccount = "hub-credentials-v1"

    func testAlwaysAllowCoversAllHubsAfterRelaunch() {
        let keychain = FakeKeychainClient()
        let original = KeychainService(keychain: keychain)
        XCTAssertTrue(original.saveCredential("fixture-a", for: "hub-a"))
        XCTAssertTrue(original.saveCredential("fixture-b", for: "hub-b"))

        // Model a new app identity: Always Allow authorizes each requested item.
        keychain.authorizedAccounts.removeAll()
        let relaunched = KeychainService(keychain: keychain)
        XCTAssertEqual(relaunched.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertEqual(relaunched.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertEqual(keychain.authorizationRequests, 1)
    }

    func testUpdatingCredentialKeepsOtherHubsAndTheAuthorizedItem() {
        let keychain = FakeKeychainClient()
        let store = KeychainService(keychain: keychain)
        XCTAssertTrue(store.saveCredential("fixture-a", for: "hub-a"))
        XCTAssertTrue(store.saveCredential("fixture-b", for: "hub-b"))
        keychain.deletions.removeAll()
        XCTAssertTrue(store.saveCredential("updated-a", for: "hub-a"))

        let relaunched = KeychainService(keychain: keychain)
        XCTAssertEqual(relaunched.loadCredential(for: "hub-a"), "updated-a")
        XCTAssertEqual(relaunched.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertEqual(keychain.items.count, 1)
        XCTAssertFalse(keychain.deletions.contains(vaultAccount))
        XCTAssertEqual(keychain.authorizationRequests, 0)
    }

    func testLegacyEntriesMigrateOnceAndThenShareAuthorization() {
        let keychain = FakeKeychainClient()
        keychain.items = ["hub-a": Data("fixture-a".utf8), "hub-b": Data("fixture-b".utf8)]
        let store = KeychainService(keychain: keychain)
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertEqual(store.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertEqual(keychain.authorizationRequests, 2, "Existing entries still require their own authorization during migration")
        XCTAssertEqual(Set(keychain.items.keys), [vaultAccount])

        keychain.authorizedAccounts.removeAll()
        keychain.authorizationRequests = 0
        keychain.reads.removeAll()
        let relaunched = KeychainService(keychain: keychain)
        XCTAssertEqual(relaunched.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertEqual(relaunched.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertEqual(keychain.authorizationRequests, 1)
        XCTAssertEqual(keychain.reads, [vaultAccount])
    }

    func testFailedMigrationPreservesLegacyCredentialForRetry() {
        let keychain = FakeKeychainClient()
        keychain.items["hub-a"] = Data("fixture-a".utf8)
        keychain.addFailure = errSecInteractionNotAllowed
        let store = KeychainService(keychain: keychain)
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertNotNil(keychain.items["hub-a"])
        XCTAssertTrue(keychain.deletions.isEmpty)

        keychain.addFailure = nil
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertNil(keychain.items["hub-a"])
        XCTAssertNotNil(keychain.items[vaultAccount])
    }

    func testDeniedVaultDoesNotFallBackToLegacyOrOverwriteAnything() {
        let keychain = FakeKeychainClient()
        keychain.items["hub-a"] = Data("fixture-a".utf8)
        keychain.readFailures[vaultAccount] = errSecAuthFailed
        let store = KeychainService(keychain: keychain)
        XCTAssertNil(store.loadCredential(for: "hub-a"))
        XCTAssertFalse(store.saveCredential("replacement", for: "hub-a"))
        XCTAssertFalse(store.deleteCredential(for: "hub-a"))
        XCTAssertEqual(keychain.items, ["hub-a": Data("fixture-a".utf8)])
        XCTAssertFalse(keychain.reads.contains("hub-a"))
        XCTAssertTrue(keychain.deletions.isEmpty)
    }

    func testCorruptOrUnsupportedVaultIsNeverOverwritten() {
        for data in [Data("invalid-json".utf8), Data(#"{"version":99,"credentials":{},"migratedAccounts":[]}"#.utf8)] {
            let keychain = FakeKeychainClient()
            keychain.items[vaultAccount] = data
            let store = KeychainService(keychain: keychain)
            XCTAssertNil(store.loadCredential(for: "hub-a"))
            XCTAssertFalse(store.saveCredential("replacement", for: "hub-a"))
            XCTAssertFalse(store.deleteCredential(for: "hub-a"))
            XCTAssertEqual(keychain.items[vaultAccount], data)
        }
    }

    func testFailedUpdateDoesNotReplaceCachedOrPersistedCredential() {
        let keychain = FakeKeychainClient()
        let store = KeychainService(keychain: keychain)
        XCTAssertTrue(store.saveCredential("original", for: "hub-a"))
        keychain.updateFailure = errSecAuthFailed
        XCTAssertFalse(store.saveCredential("replacement", for: "hub-a"))
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "original")
        XCTAssertEqual(KeychainService(keychain: keychain).loadCredential(for: "hub-a"), "original")
    }

    func testFailedMigrationIntoExistingVaultPreservesBothSources() {
        let keychain = FakeKeychainClient()
        let store = KeychainService(keychain: keychain)
        XCTAssertTrue(store.saveCredential("fixture-a", for: "hub-a"))
        keychain.items["hub-b"] = Data("fixture-b".utf8)
        keychain.updateFailure = errSecInteractionNotAllowed
        XCTAssertEqual(store.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertNotNil(keychain.items["hub-b"])
        XCTAssertEqual(KeychainService(keychain: keychain).loadCredential(for: "hub-a"), "fixture-a")
        keychain.updateFailure = nil
        XCTAssertEqual(store.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertNil(keychain.items["hub-b"])
    }

    func testFailedDeletionPreservesCachedAndPersistedCredential() {
        let keychain = FakeKeychainClient()
        let store = KeychainService(keychain: keychain)
        XCTAssertTrue(store.saveCredential("fixture-a", for: "hub-a"))
        keychain.updateFailure = errSecAuthFailed
        XCTAssertFalse(store.deleteCredential(for: "hub-a"))
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertEqual(KeychainService(keychain: keychain).loadCredential(for: "hub-a"), "fixture-a")
    }

    func testDeniedLegacyCredentialCanBeMigratedOnRetry() {
        let keychain = FakeKeychainClient()
        keychain.items["hub-a"] = Data("fixture-a".utf8)
        keychain.readFailures["hub-a"] = errSecUserCanceled
        let store = KeychainService(keychain: keychain)
        XCTAssertNil(store.loadCredential(for: "hub-a"))
        XCTAssertNotNil(keychain.items["hub-a"])
        XCTAssertNil(keychain.items[vaultAccount])
        keychain.readFailures.removeAll()
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertNil(keychain.items["hub-a"])
    }

    func testDeletingOneHubPreservesOthersAndDoesNotRestoreLeftoverLegacyEntry() {
        let keychain = FakeKeychainClient()
        keychain.items["hub-a"] = Data("old-a".utf8)
        keychain.deleteFailure = errSecAuthFailed
        let store = KeychainService(keychain: keychain)
        XCTAssertEqual(store.loadCredential(for: "hub-a"), "old-a")
        XCTAssertTrue(store.saveCredential("fixture-b", for: "hub-b"))
        XCTAssertTrue(store.deleteCredential(for: "hub-a"))
        XCTAssertNotNil(keychain.items["hub-a"], "Simulate a legacy entry whose cleanup was refused")

        let relaunched = KeychainService(keychain: keychain)
        XCTAssertNil(relaunched.loadCredential(for: "hub-a"))
        XCTAssertEqual(relaunched.loadCredential(for: "hub-b"), "fixture-b")
    }

    func testDeletingLastHubKeepsTheVaultAndItsAuthorization() {
        let keychain = FakeKeychainClient()
        let store = KeychainService(keychain: keychain)
        XCTAssertTrue(store.saveCredential("fixture-a", for: "hub-a"))
        XCTAssertTrue(store.deleteCredential(for: "hub-a"))
        XCTAssertNotNil(keychain.items[vaultAccount])
        XCTAssertNil(KeychainService(keychain: keychain).loadCredential(for: "hub-a"))
        XCTAssertTrue(store.saveCredential("fixture-b", for: "hub-b"))
        XCTAssertEqual(keychain.authorizationRequests, 0)
    }

    func testSavingRefreshesTheVaultBeforeMergingAnotherHubsCredential() {
        let keychain = FakeKeychainClient()
        let first = KeychainService(keychain: keychain)
        XCTAssertTrue(first.saveCredential("fixture-a", for: "hub-a"))
        let second = KeychainService(keychain: keychain)
        XCTAssertEqual(second.loadCredential(for: "hub-a"), "fixture-a")
        XCTAssertTrue(first.saveCredential("fixture-b", for: "hub-b"))
        XCTAssertTrue(second.saveCredential("fixture-c", for: "hub-c"))
        let relaunched = KeychainService(keychain: keychain)
        XCTAssertEqual(relaunched.loadCredential(for: "hub-b"), "fixture-b")
        XCTAssertEqual(relaunched.loadCredential(for: "hub-c"), "fixture-c")
    }
}

private final class FakeKeychainClient: KeychainClient {
    var items: [String: Data] = [:]
    var authorizedAccounts: Set<String> = []
    var authorizationRequests = 0
    var reads: [String] = []
    var deletions: [String] = []
    var readFailures: [String: OSStatus] = [:]
    var updateFailure: OSStatus?
    var addFailure: OSStatus?
    var deleteFailure: OSStatus?

    func read(_ query: [String: Any]) -> (OSStatus, Data?) {
        let account = query[kSecAttrAccount as String] as! String
        reads.append(account)
        if let failure = readFailures[account] { return (failure, nil) }
        guard let data = items[account] else { return (errSecItemNotFound, nil) }
        if query[kSecReturnData as String] as? Bool == true,
           authorizedAccounts.insert(account).inserted {
            authorizationRequests += 1
        }
        return (errSecSuccess, data)
    }

    func add(_ attributes: [String: Any]) -> OSStatus {
        if let addFailure { return addFailure }
        let account = attributes[kSecAttrAccount as String] as! String
        guard items[account] == nil else { return errSecDuplicateItem }
        items[account] = attributes[kSecValueData as String] as? Data
        authorizedAccounts.insert(account)
        return errSecSuccess
    }

    func update(_ query: [String: Any], attributes: [String: Any]) -> OSStatus {
        if let updateFailure { return updateFailure }
        let account = query[kSecAttrAccount as String] as! String
        guard items[account] != nil else { return errSecItemNotFound }
        items[account] = attributes[kSecValueData as String] as? Data
        return errSecSuccess
    }

    func delete(_ query: [String: Any]) -> OSStatus {
        if let deleteFailure { return deleteFailure }
        let account = query[kSecAttrAccount as String] as! String
        deletions.append(account)
        authorizedAccounts.remove(account)
        return items.removeValue(forKey: account) == nil ? errSecItemNotFound : errSecSuccess
    }
}
