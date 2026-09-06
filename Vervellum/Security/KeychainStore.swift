import Foundation
import Security

/// Stores Vervellum's API keys as generic-password items in the login keychain.
///
/// Keys never touch `UserDefaults` or the settings file: those are readable by anything
/// running as the user and get swept into backups and screen shares. The Keychain is the
/// only local store macOS gives an unsandboxed app that is encrypted at rest and
/// access-controlled per application.
///
/// No `kSecAttrAccessible` is set, and that is deliberate rather than an omission: on
/// macOS it applies only to the *data protection* keychain, which in turn derives its
/// access groups from entitlements authorized by a provisioning profile. Opting in
/// (`kSecUseDataProtectionKeychain`) without that provisioning makes every call fail with
/// `errSecMissingEntitlement`. Against the default file-based keychain the attribute is
/// silently ignored, so passing it would be documentation that lies. Items are protected
/// by the login keychain's own unlock state and ACL.
///
/// This is the macOS half of the shared `SecretStore` seam; the Linux build supplies its
/// own, weaker, implementation and says so.
final class KeychainStore: SecretStore {

    /// The keychain service name; one per app so two L-K-M apps never collide.
    let service: String

    var backendDescription: String { "your login Keychain" }

    init(service: String = AppIdentity.bundleIdentifier) {
        self.service = service
    }

    enum KeychainError: LocalizedError {
        case unexpectedStatus(OSStatus)
        case unreadableValue

        var errorDescription: String? {
            switch self {
            case .unexpectedStatus(let status):
                let detail = SecCopyErrorMessageString(status, nil) as String?
                return "Keychain error \(status)\(detail.map { ": \($0)" } ?? "")."
            case .unreadableValue:
                return "The stored key could not be read as text."
            }
        }
    }

    // MARK: Read

    /// The stored secret for `account`, or nil when absent.
    ///
    /// A read failure other than "not found" is reported as nil rather than thrown:
    /// callers treat a missing key as "not configured yet", and a keychain that is
    /// momentarily unavailable should read the same way rather than crashing a research
    /// run. The status is logged so it is still diagnosable.
    func value(for account: SecretAccount) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else {
            if status != errSecItemNotFound {
                NSLog("Vervellum: keychain read for '\(account.rawValue)' failed with status \(status)")
            }
            return nil
        }
        guard let data = item as? Data, let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string.isEmpty ? nil : string
    }

    // MARK: Write

    /// Stores `secret` for `account`, replacing any existing item. An empty or
    /// whitespace-only secret deletes the item instead — "clear the field and save" is
    /// how a user removes a key, and leaving an empty item behind would make
    /// `hasValue(for:)` lie.
    func set(_ secret: String, for account: SecretAccount) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { try delete(account); return }
        guard let data = trimmed.data(using: .utf8) else { throw KeychainError.unreadableValue }

        // Update-then-insert rather than insert-then-update: an add against an existing
        // (service, account) pair fails with `errSecDuplicateItem`, so insert-first would
        // take the error path on every ordinary key change. It also beats
        // delete-then-insert, which has a window where the key is simply gone.
        // `attributesToUpdate` carries only the change; the query identifies the item and
        // must not contain `kSecValueData`.
        let updateStatus = SecItemUpdate(baseQuery(account: account) as CFDictionary,
                                         [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(updateStatus)
        }

        var insert = baseQuery(account: account)
        insert[kSecValueData as String] = data
        insert[kSecAttrLabel as String] = "Vervellum — \(account.rawValue)"
        let addStatus = SecItemAdd(insert as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainError.unexpectedStatus(addStatus)
        }
    }

    /// Removes the stored secret. Succeeds when nothing was stored.
    func delete(_ account: SecretAccount) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    // MARK: Helpers

    private func baseQuery(account: SecretAccount) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account.rawValue,
        ]
    }
}
