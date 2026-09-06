import Foundation

/// Who the application says it is when it talks to a provider.
///
/// Shared rather than per-platform because the providers see it: the MCP handshake
/// sends a client name and version, and GitHub's API requires a User-Agent. A macOS
/// build reporting one identity and a Linux build another would make a support
/// question ("which version sent this?") unanswerable.
///
/// The version is read from the bundle where there is one — that is where the macOS
/// release process stamps `MARKETING_VERSION` — and falls back to a constant the Linux
/// build keeps in step through its own packaging script.
enum AppIdentity {

    static let name = "Vervellum"

    /// Reverse-DNS identity. On Linux this one string is also the D-Bus name, the
    /// `.desktop` basename and `StartupWMClass`; all three break silently if they
    /// diverge.
    static let bundleIdentifier = "ch.lkmc.Vervellum"

    /// The fallback version, kept in step with `MARKETING_VERSION` and the `.deb`.
    static let fallbackVersion = "0.1.0"

    static let version: String = {
        let fromBundle = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        guard let fromBundle, !fromBundle.isEmpty, fromBundle != "0" else { return fallbackVersion }
        return fromBundle
    }()

    /// `Vervellum/0.1.0` — for a User-Agent.
    static var userAgent: String { "\(name)/\(version)" }
}
