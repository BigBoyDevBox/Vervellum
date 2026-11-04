import Foundation

/// Where non-secret settings live.
///
/// `UserDefaults` on macOS, a JSON file under `$XDG_CONFIG_HOME` on Linux. The protocol
/// is untyped-by-key on purpose: clamping, defaults and validation belong in
/// `CorePreferences`, which is shared, so a platform cannot accidentally ship a
/// different idea of what a valid panel width is.
protocol SettingsStore: AnyObject {
    func contains(_ key: String) -> Bool
    func string(for key: String) -> String?
    func double(for key: String) -> Double?
    func bool(for key: String) -> Bool?
    func setString(_ value: String?, for key: String)
    func setDouble(_ value: Double?, for key: String)
    func setBool(_ value: Bool?, for key: String)
    /// Blocks until preceding writes are durable, and reports whether they made it.
    /// Most settings tolerate best-effort persistence; provider credentials do not,
    /// because a fixed Keychain replacement may be written only after its destination
    /// will survive a process crash.
    func synchronize() -> Bool
}

/// An in-memory store. Tests use it so they never touch the real user's settings.
final class MemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]

    init(_ initial: [String: Any] = [:]) { values = initial }

    func contains(_ key: String) -> Bool { values[key] != nil }
    func string(for key: String) -> String? { values[key] as? String }
    func double(for key: String) -> Double? { values[key] as? Double }
    func bool(for key: String) -> Bool? { values[key] as? Bool }

    func setString(_ value: String?, for key: String) { values[key] = value }
    func setDouble(_ value: Double?, for key: String) { values[key] = value }
    func setBool(_ value: Bool?, for key: String) { values[key] = value }
    func synchronize() -> Bool { true }
}

/// A JSON file of settings, written atomically.
///
/// Reads are served from memory after the first load, because settings are read on
/// every UI redraw and a file hit per read would be absurd. Writes are immediate rather
/// than debounced: settings change at human speed, and a preference the user just set
/// must survive a crash a second later.
///
/// A file that fails to parse reads as empty rather than blocking launch. Writes
/// preserve an unreadable file until it is repaired, rather than erasing external edits.
final class JSONFileSettingsStore: SettingsStore {

    private let url: URL
    private var values: [String: Any]

    init(url: URL) {
        self.url = url
        if let data = try? Data(contentsOf: url),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            values = object
        } else {
            values = [:]
        }
    }

    func contains(_ key: String) -> Bool { values[key] != nil }
    func string(for key: String) -> String? { values[key] as? String }
    func bool(for key: String) -> Bool? { values[key] as? Bool }

    /// JSON has one number type, so an integer written as `1` comes back as `Int` and
    /// must still satisfy a `Double` read.
    func double(for key: String) -> Double? {
        if let value = values[key] as? Double { return value }
        if let value = values[key] as? Int { return Double(value) }
        return nil
    }

    func setString(_ value: String?, for key: String) { write(value, key) }
    func setDouble(_ value: Double?, for key: String) { write(value, key) }
    func setBool(_ value: Bool?, for key: String) { write(value, key) }
    /// Every ordinary setter already flushes. Repeating the complete atomic write here
    /// gives credential transactions a checked durability boundary of their own — except
    /// over a file that exists but no longer parses. The setters refuse to replace such
    /// a file (see `write`), so the barrier fails closed rather than being the write
    /// that does: a credential transaction then stops before deleting anything.
    func synchronize() -> Bool {
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try? Data(contentsOf: url)
            let parsed = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
            guard parsed != nil else { return false }
        }
        return flush()
    }

    private func write(_ value: Any?, _ key: String) {
        // Linux users edit this file directly; preserve unrelated edits between writes.
        let data = try? Data(contentsOf: url)
        let current = data.flatMap { (try? JSONSerialization.jsonObject(with: $0)) as? [String: Any] }
        let exists = FileManager.default.fileExists(atPath: url.path)
        if let current { values = current } else if !exists { values = [:] }
        if let value { values[key] = value } else { values.removeValue(forKey: key) }

        // Keep in-session changes usable even when persistence must preserve a damaged file.
        guard current != nil || !exists else {
            FileHandle.standardError.write(Data(
                "vervellum warning: settings are unreadable; no changes were saved\n".utf8))
            return
        }
        _ = flush()
    }

    private func flush() -> Bool {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: [.atomic])
            return true
        } catch {
            // Not fatal, and deliberately not surfaced: a settings write failing is a
            // disk problem the app cannot fix, and an alert per keystroke would be worse
            // than the lost setting.
            FileHandle.standardError.write(Data("vervellum warning: could not save settings\n".utf8))
            return false
        }
    }
}
