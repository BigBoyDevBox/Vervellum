#if os(Linux)
import Foundation

/// Where Vervellum keeps its files on Linux.
///
/// These are read from the XDG environment directly rather than through
/// `FileManager.url(for:in:)`. On Linux, Foundation hard-codes `~/.local/share` for
/// `.applicationSupportDirectory` and **ignores `XDG_DATA_HOME` entirely**, so a user
/// who has relocated their data directory would silently get the wrong path.
///
/// The specification's fallback rule is followed exactly: a variable that is unset
/// *or empty* falls back, and a value that is not an absolute path is invalid and also
/// falls back. Treating an empty value as set is the usual bug.
enum LinuxPaths {

    static let applicationName = "vervellum"

    /// `$XDG_CONFIG_HOME/vervellum`, else `~/.config/vervellum`.
    static var configDirectory: URL {
        directory(environment: "XDG_CONFIG_HOME", fallback: ".config")
            .appendingPathComponent(applicationName, isDirectory: true)
    }

    /// `$XDG_DATA_HOME/vervellum`, else `~/.local/share/vervellum`.
    static var dataDirectory: URL {
        directory(environment: "XDG_DATA_HOME", fallback: ".local/share")
            .appendingPathComponent(applicationName, isDirectory: true)
    }

    static var settingsFile: URL { configDirectory.appendingPathComponent("settings.json") }
    static var secretsFile: URL { configDirectory.appendingPathComponent("secrets.json") }
    static var threadsFile: URL { dataDirectory.appendingPathComponent("threads.json") }

    private static func directory(environment key: String, fallback: String) -> URL {
        if let value = ProcessInfo.processInfo.environment[key],
           !value.isEmpty,
           value.hasPrefix("/") {
            return URL(fileURLWithPath: value, isDirectory: true)
        }
        return home.appendingPathComponent(fallback, isDirectory: true)
    }

    private static var home: URL {
        // `NSHomeDirectory()` consults $HOME and then the passwd database, which is the
        // behaviour wanted here — including for a service account with no $HOME set.
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }
}
#endif
