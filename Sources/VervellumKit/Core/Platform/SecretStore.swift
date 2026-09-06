import Foundation

/// Where API keys live.
///
/// Every platform has a different answer — the login Keychain on macOS, the Secret
/// Service on a Linux desktop, a mode-0600 file when there is no keyring at all — and
/// they are not equally strong. The protocol therefore carries `backendDescription`, so
/// Settings can tell the user *which* one is in use rather than implying they are
/// interchangeable.
protocol SecretStore: AnyObject {
    /// The stored secret, or nil when absent or unreadable.
    func value(for account: SecretAccount) -> String?
    /// Stores `secret`, replacing any existing value. An empty or whitespace-only
    /// secret deletes the item — "clear the field and save" is how a user removes a
    /// key, and leaving an empty item behind would make `hasValue(for:)` lie.
    func set(_ secret: String, for account: SecretAccount) throws
    func delete(_ account: SecretAccount) throws
    /// A short phrase naming the backend, for Settings. E.g. "your login Keychain".
    var backendDescription: String { get }
}

extension SecretStore {
    func hasValue(for account: SecretAccount) -> Bool { value(for: account) != nil }
}

/// The secrets Vervellum stores. An enum rather than free strings so a typo cannot
/// silently create a second, empty slot that reads as "not configured".
enum SecretAccount: String, CaseIterable {
    /// The OpenAI-compatible Chat Completions provider key.
    case modelAPIKey = "model-api-key"
    /// The key for the web-search MCP endpoint.
    case searchAPIKey = "search-api-key"
}

/// Holds secrets for the life of the process only. Used by tests, and by any run that
/// has no usable backend — losing the key on quit is better than writing it somewhere
/// the user was not told about.
final class EphemeralSecretStore: SecretStore {
    private var values: [SecretAccount: String] = [:]

    var backendDescription: String { "this session only (nothing is stored on disk)" }

    func value(for account: SecretAccount) -> String? { values[account] }

    func set(_ secret: String, for account: SecretAccount) throws {
        let trimmed = secret.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { values[account] = nil } else { values[account] = trimmed }
    }

    func delete(_ account: SecretAccount) throws { values[account] = nil }
}
