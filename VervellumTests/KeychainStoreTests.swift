import Security
import XCTest
@testable import Vervellum

final class KeychainStoreTests: XCTestCase {

    /// `set` is the general `SecretStore` API, not only the provider transaction's:
    /// a caller replacing an existing credential must get it back when the required
    /// downgrade mirror fails, not lose it to the rollback.
    func testLegacyMirrorFailureRestoresAPreExistingBlobValue() throws {
        let fake = FakeKeychainOperations()
        let account = SecretAccount(rawValue: "provider")
        fake.items["all-api-keys"] = try SecretBlob.encode([account.rawValue: "old key"])
        fake.items[account.rawValue] = Data("old key".utf8)
        fake.updateFailures[account.rawValue] = errSecAuthFailed
        let store = KeychainStore(service: uniqueService(), operations: fake.interface)

        XCTAssertThrowsError(try store.set("new key", for: account))
        let blob = try XCTUnwrap(fake.items["all-api-keys"])
        XCTAssertEqual(SecretBlob.decode(blob)?[account.rawValue], "old key",
                       "rollback must restore the previous credential, not erase it")
        XCTAssertEqual(store.value(for: account), "old key",
                       "the pre-existing credential must remain readable")
    }

    func testLegacyMirrorFailureIsReported() throws {
        let fake = FakeKeychainOperations()
        let account = SecretAccount(rawValue: "provider")
        fake.updateFailures[account.rawValue] = errSecAuthFailed
        let store = KeychainStore(service: uniqueService(), operations: fake.interface)

        XCTAssertThrowsError(try store.set("new key", for: account))
        XCTAssertTrue(fake.items.keys.contains("all-api-keys"),
                      "the authoritative write happened before the mirror failed")
        XCTAssertNil(SecretBlob.decode(try XCTUnwrap(fake.items["all-api-keys"]))?[account.rawValue],
                     "the authoritative value must roll back when its required mirror fails")
        XCTAssertFalse(fake.items.keys.contains(account.rawValue))
    }

    func testBlobFailureDoesNotAttemptTheLegacyMirror() {
        let fake = FakeKeychainOperations()
        let account = SecretAccount(rawValue: "provider")
        fake.addFailures["all-api-keys"] = errSecAuthFailed
        let store = KeychainStore(service: uniqueService(), operations: fake.interface)

        XCTAssertThrowsError(try store.set("new key", for: account))
        XCTAssertFalse(fake.operations.contains { $0.hasSuffix(":provider") },
                       "a failed authoritative write must stop before the mirror")
    }

    func testSuccessfulSetUpdatesBlobAndLegacyItem() throws {
        let fake = FakeKeychainOperations()
        let account = SecretAccount(rawValue: "provider")
        let store = KeychainStore(service: uniqueService(), operations: fake.interface)

        try store.set("  new key  ", for: account)

        XCTAssertEqual(String(data: try XCTUnwrap(fake.items[account.rawValue]), encoding: .utf8),
                       "new key")
        let blob = try XCTUnwrap(fake.items["all-api-keys"])
        XCTAssertEqual(SecretBlob.decode(blob)?[account.rawValue], "new key")
    }

    func testLegacyDeleteFailureLeavesAuthoritativeBlobUntouched() throws {
        let fake = FakeKeychainOperations()
        let account = SecretAccount(rawValue: "provider")
        fake.items["all-api-keys"] = try SecretBlob.encode([account.rawValue: "old key"])
        fake.items[account.rawValue] = Data("old key".utf8)
        fake.deleteFailures[account.rawValue] = errSecAuthFailed
        let store = KeychainStore(service: uniqueService(), operations: fake.interface)

        XCTAssertThrowsError(try store.delete(account))

        let blob = try XCTUnwrap(fake.items["all-api-keys"])
        XCTAssertEqual(SecretBlob.decode(blob)?[account.rawValue], "old key")
    }

    private func uniqueService() -> String {
        "ch.lkmc.Vervellum.KeychainStoreTests.\(UUID().uuidString)"
    }
}

private final class FakeKeychainOperations {
    var items: [String: Data] = [:]
    var updateFailures: [String: OSStatus] = [:]
    var addFailures: [String: OSStatus] = [:]
    var deleteFailures: [String: OSStatus] = [:]
    var operations: [String] = []

    lazy var interface = KeychainOperations(
        copyMatching: { [unowned self] query, result in
            let account = self.account(in: query)
            self.operations.append("copy:\(account)")
            // Both halves of the real contract: a miss still initialises the result
            // pointer, and a hit hands back an object the caller owns at +1 —
            // `passRetained`, because `CFRetain` itself is unavailable in Swift.
            guard let value = self.items[account] else {
                result?.pointee = nil
                return errSecItemNotFound
            }
            result?.pointee = Unmanaged.passRetained(value as CFData).takeUnretainedValue()
            return errSecSuccess
        },
        update: { [unowned self] query, attributes in
            let account = self.account(in: query)
            self.operations.append("update:\(account)")
            if let status = self.updateFailures[account] { return status }
            guard self.items[account] != nil else { return errSecItemNotFound }
            self.items[account] = self.data(in: attributes)
            return errSecSuccess
        },
        add: { [unowned self] attributes, _ in
            let account = self.account(in: attributes)
            self.operations.append("add:\(account)")
            if let status = self.addFailures[account] { return status }
            guard self.items[account] == nil else { return errSecDuplicateItem }
            self.items[account] = self.data(in: attributes)
            return errSecSuccess
        },
        delete: { [unowned self] query in
            let account = self.account(in: query)
            self.operations.append("delete:\(account)")
            if let status = self.deleteFailures[account] { return status }
            return self.items.removeValue(forKey: account) == nil
                ? errSecItemNotFound : errSecSuccess
        })

    private func account(in dictionary: CFDictionary) -> String {
        (dictionary as NSDictionary)[kSecAttrAccount] as? String ?? ""
    }

    private func data(in dictionary: CFDictionary) -> Data {
        (dictionary as NSDictionary)[kSecValueData] as? Data ?? Data()
    }
}
