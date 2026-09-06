import AppKit
import ApplicationServices

/// Reads the frontmost application's selected text, for the
/// "research the selection" shortcut.
///
/// This is the **only** feature in Vervellum that needs a system permission, and it
/// is off by default for exactly that reason: summoning the panel and typing a
/// question must work the second the app is launched, with no trip to System
/// Settings.
///
/// The Accessibility API is used rather than the obvious alternative of synthesising
/// a ⌘C keystroke. Synthetic copying is worse in every way that matters here: it
/// clobbers the user's clipboard, it needs the same permission anyway (posting
/// events requires Accessibility), it silently fails in apps that bind ⌘C to
/// something else, and it races the target app's own copy handling. Reading the
/// attribute is a passive query with no side effects.
///
/// Every failure path returns nil. An app that does not implement the attribute
/// (many web views, most canvas apps) is normal, not an error, and the composer
/// simply opens empty.
enum SelectedTextReader {

    /// Upper bound on seeded text. A user who selects an entire document and hits
    /// the shortcut should get a usable excerpt, not a request that blows the
    /// model's context and fails.
    static let maxLength = 8_000

    /// Whether the user has granted Accessibility access. Never prompts.
    static var isAuthorized: Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: false] as CFDictionary)
    }

    /// Asks macOS to show the Accessibility prompt, if it has not been shown.
    ///
    /// The prompt appears once per app bundle per system; after that macOS silently
    /// does nothing, which is why Settings also offers a direct link to the pane. The
    /// return value is *not* the outcome — prompting is asynchronous and the call
    /// reports the state as it was — so callers poll `isAuthorized` instead.
    @discardableResult
    static func requestAuthorization() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// Remembers that the grant was once held, so its silent loss can be detected.
    ///
    /// TCC keys an Accessibility grant to the code signature. Release builds are
    /// ad-hoc signed, and an ad-hoc signature's cdhash changes with **every build** —
    /// so every update silently revokes the grant. Without this flag the feature would
    /// simply stop working with no explanation, which is the worst possible outcome for
    /// a permission the user deliberately gave.
    private static let grantedKey = "accessibilityWasGranted"

    /// True when Accessibility was granted at some point and is not granted now — the
    /// signature-change case. Callers use it to offer a re-grant rather than a
    /// first-time explanation.
    static func grantWasRevoked(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: grantedKey) && !isAuthorized
    }

    /// Records the current state, so a later loss is detectable. Call after a
    /// successful read.
    static func rememberGrant(defaults: UserDefaults = .standard) {
        if isAuthorized { defaults.set(true, forKey: grantedKey) }
    }

    /// Opens System Settings at Privacy & Security ▸ Accessibility.
    static func openAccessibilitySettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// The selected text in the frontmost application, or nil.
    ///
    /// `frontmostApplication` must be read *before* the panel is shown — once
    /// Vervellum activates, it is itself the frontmost app.
    static func selectedText(in application: NSRunningApplication? = NSWorkspace.shared.frontmostApplication)
        -> String? {
        guard isAuthorized else { return nil }
        guard let application,
              application.processIdentifier != NSRunningApplication.current.processIdentifier
        else { return nil }

        let app = AXUIElementCreateApplication(application.processIdentifier)
        guard let focused = copyElement(app, kAXFocusedUIElementAttribute as String) else { return nil }

        if let text = copyString(focused, kAXSelectedTextAttribute as String), !text.isEmpty {
            return trim(text)
        }
        // Some apps expose the selection one level up, on the text area that owns the
        // focused element rather than on the element itself.
        if let parent = copyElement(focused, kAXParentAttribute as String),
           let text = copyString(parent, kAXSelectedTextAttribute as String), !text.isEmpty {
            return trim(text)
        }
        return nil
    }

    // MARK: Attribute plumbing

    private static func copyElement(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let value else { return nil }
        // Verify the type before bridging: an app is free to return anything, and a
        // blind cast would be a crash waiting for the first one that does.
        guard CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }

    private static func copyString(_ element: AXUIElement, _ attribute: String) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success,
              let text = value as? String else { return nil }
        return text
    }

    /// Trims surrounding whitespace and caps the length on a word boundary.
    static func trim(_ text: String, limit: Int = maxLength) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > limit else { return trimmed }
        let cut = trimmed.prefix(limit)
        if let space = cut.lastIndex(of: " "), cut.distance(from: cut.startIndex, to: space) > limit / 2 {
            return String(cut[..<space]) + "…"
        }
        return cut + "…"
    }
}
