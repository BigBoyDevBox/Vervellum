import Foundation

/// Where non-secret settings live.
///
/// `UserDefaults` on macOS, a JSON file under `$XDG_CONFIG_HOME` on Linux. The protocol
/// is untyped-by-key on purpose: clamping, defaults and validation belong in
/// `CorePreferences`, which is shared, so a platform cannot accidentally ship a
/// different idea of what a valid panel width is.
protocol SettingsStore: AnyObject {
    func string(for key: String) -> String?
    func double(for key: String) -> Double?
    func bool(for key: String) -> Bool?
    func setString(_ value: String?, for key: String)
    func setDouble(_ value: Double?, for key: String)
    func setBool(_ value: Bool?, for key: String)
}

/// An in-memory store. Tests use it so they never touch the real user's settings.
final class MemorySettingsStore: SettingsStore {
    private var values: [String: Any] = [:]

    init(_ initial: [String: Any] = [:]) { values = initial }

    func string(for key: String) -> String? { values[key] as? String }
    func double(for key: String) -> Double? { values[key] as? Double }
    func bool(for key: String) -> Bool? { values[key] as? Bool }

    func setString(_ value: String?, for key: String) { values[key] = value }
    func setDouble(_ value: Double?, for key: String) { values[key] = value }
    func setBool(_ value: Bool?, for key: String) { values[key] = value }
}

/// A JSON file of settings, written atomically.
///
/// Reads are served from memory after the first load, because settings are read on
/// every UI redraw and a file hit per read would be absurd. Writes are immediate rather
/// than debounced: settings change at human speed, and a preference the user just set
/// must survive a crash a second later.
///
/// A file that fails to parse is treated as empty rather than fatal. Losing preferences
/// is annoying; refusing to launch because of them is worse.
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

    private func write(_ value: Any?, _ key: String) {
        if let value { values[key] = value } else { values.removeValue(forKey: key) }
        flush()
    }

    private func flush() {
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: values,
                                                  options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: [.atomic])
        } catch {
            // Not fatal, and deliberately not surfaced: a settings write failing is a
            // disk problem the app cannot fix, and an alert per keystroke would be worse
            // than the lost setting.
            FileHandle.standardError.write(Data("vervellum warning: could not save settings\n".utf8))
        }
    }
}
