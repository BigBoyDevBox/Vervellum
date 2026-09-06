import Foundation

/// The settings both front ends share, with their defaults, keys and clamping in one
/// place.
///
/// Platform-specific settings deliberately stay out: the macOS panel's edge, width and
/// dismissal behaviour, its global shortcuts and its login item have no Linux
/// equivalent (a GNOME Wayland compositor will not let an application place its own
/// window, and the shortcut is registered with the desktop environment rather than
/// grabbed by the app). Each platform's own preferences type owns those and forwards
/// the shared ones here, so a change to a shared default reaches both.
///
/// Numeric values are clamped **on read as well as on write**, so a settings file
/// corrupted by a crash, an interrupted sync, or a hand edit cannot produce a state the
/// user can neither see nor fix.
final class CorePreferences {

    /// Invoked after any change, so a platform can republish it — `objectWillChange` on
    /// macOS, a redraw on Linux.
    var onChange: (() -> Void)?

    private let store: SettingsStore

    init(store: SettingsStore) {
        self.store = store
    }

    // MARK: Defaults

    enum Default {
        static let modelEndpoint = ""
        static let modelName = ""
        static let searchEndpoint = ProviderSettings.defaultSearchEndpoint
        static let historyEnabled = true
        /// The search-plan and sources trail above each answer.
        static let showProcessTrail = true
        /// Return submits; Shift-Return inserts a newline. The inverse suits people who
        /// write long multi-paragraph questions.
        static let submitOnReturn = true
        /// On. A false positive costs a re-typed word; a false negative sends a live
        /// credential to a third party.
        static let redactSecrets = true
        static let textScale = 1.0
    }

    enum Key {
        static let modelEndpoint = "modelEndpoint"
        static let modelName = "modelName"
        static let searchEndpoint = "searchEndpoint"
        static let historyEnabled = "historyEnabled"
        static let showProcessTrail = "showProcessTrail"
        static let submitOnReturn = "submitOnReturn"
        static let redactSecrets = "redactSecrets"
        static let textScale = "textScale"
    }

    /// Body-text scale for the thread. The panel is narrow and often sits on a display
    /// the user is not sitting square to; one slider beats guessing a good size.
    static let textScaleRange: ClosedRange<Double> = 0.85...1.4

    // MARK: Providers

    var providerSettings: ProviderSettings {
        get {
            ProviderSettings(
                modelEndpoint: store.string(for: Key.modelEndpoint) ?? Default.modelEndpoint,
                modelName: store.string(for: Key.modelName) ?? Default.modelName,
                searchEndpoint: store.string(for: Key.searchEndpoint) ?? Default.searchEndpoint)
        }
        set {
            store.setString(newValue.modelEndpoint, for: Key.modelEndpoint)
            store.setString(newValue.modelName, for: Key.modelName)
            // An emptied search endpoint reverts to the documented default rather than
            // leaving the app with no search at all.
            let endpoint = newValue.searchEndpoint.trimmingCharacters(in: .whitespacesAndNewlines)
            store.setString(endpoint.isEmpty ? Default.searchEndpoint : endpoint, for: Key.searchEndpoint)
            onChange?()
        }
    }

    // MARK: Behaviour

    var historyEnabled: Bool {
        get { store.bool(for: Key.historyEnabled) ?? Default.historyEnabled }
        set { store.setBool(newValue, for: Key.historyEnabled); onChange?() }
    }

    var showProcessTrail: Bool {
        get { store.bool(for: Key.showProcessTrail) ?? Default.showProcessTrail }
        set { store.setBool(newValue, for: Key.showProcessTrail); onChange?() }
    }

    var submitOnReturn: Bool {
        get { store.bool(for: Key.submitOnReturn) ?? Default.submitOnReturn }
        set { store.setBool(newValue, for: Key.submitOnReturn); onChange?() }
    }

    /// Whether text captured from another application is scanned for credentials before
    /// it reaches the composer. See `SecretRedactor`.
    var redactSecrets: Bool {
        get { store.bool(for: Key.redactSecrets) ?? Default.redactSecrets }
        set { store.setBool(newValue, for: Key.redactSecrets); onChange?() }
    }

    var textScale: Double {
        get { Self.clamped(store.double(for: Key.textScale), Default.textScale, Self.textScaleRange) }
        set {
            store.setDouble(Self.clamp(newValue, Self.textScaleRange), for: Key.textScale)
            onChange?()
        }
    }

    // MARK: Platform escape hatch

    /// Reads a flag that has no shared meaning — a platform's own bookkeeping.
    ///
    /// Deliberately unglamorous and deliberately narrow. Every setting a user can see
    /// belongs above, where its default and clamping are shared; this exists so a
    /// platform does not have to stand up a second settings file for one boolean, such
    /// as "the desktop shortcut has been installed once".
    func rawBool(_ key: String) -> Bool? { store.bool(for: key) }

    func setRawBool(_ value: Bool, _ key: String) {
        store.setBool(value, for: key)
        onChange?()
    }

    // MARK: Clamping

    /// Substitutes the default for a missing, non-finite, or out-of-range value.
    /// Clamping on *read* is what makes a corrupted settings file survivable without a
    /// reset — the alternative is an app the user has to delete a plist to recover.
    static func clamped(_ stored: Double?, _ fallback: Double, _ range: ClosedRange<Double>) -> Double {
        guard let stored, stored.isFinite else { return fallback }
        return clamp(stored, range)
    }

    static func clamp(_ value: Double, _ range: ClosedRange<Double>) -> Double {
        min(max(value, range.lowerBound), range.upperBound)
    }
}
