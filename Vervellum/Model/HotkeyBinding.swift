import Carbon.HIToolbox
import KeycapKit

/// A user-configurable global hotkey: a virtual key code plus Carbon modifier
/// flags, an on/off switch, and a human label captured at record time.
/// Persisted as JSON in `UserDefaults`; registered via `CarbonHotkey` (which needs
/// no permission). See PLAN.md §5.
///
/// The combo is converted to and from Keycap's `KeyCombo` at the recorder
/// boundary; the persisted shape is Vervellum's own and must not change.
struct HotkeyBinding: Codable, Equatable {
    var keyCode: UInt32
    /// Carbon modifier-flag bits (`cmdKey | optionKey | …`).
    var modifiers: UInt32
    /// The label captured at record time, preserved in JSON for older builds.
    var keyLabel: String
    var enabled: Bool

    /// The persisted values as Keycap's combo. `HotkeyModifiers(carbonFlags:)`
    /// keeps only the four Carbon hotkey bits; caps lock and the other Cocoa
    /// flags were never part of a `RegisterEventHotKey` registration.
    var combo: KeyCombo {
        KeyCombo(keyCode: keyCode, modifiers: HotkeyModifiers(carbonFlags: modifiers))
    }

    init(keyCode: UInt32, modifiers: UInt32, keyLabel: String, enabled: Bool) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
        self.enabled = enabled
    }

    /// Builds a binding from a Keycap combo, preserving the stored label and flag.
    init(combo: KeyCombo, keyLabel: String, enabled: Bool) {
        self.init(keyCode: combo.keyCode, modifiers: combo.carbonModifiers,
                  keyLabel: keyLabel, enabled: enabled)
    }

    /// Registerable only when enabled and a usable global hotkey. Keycap's family
    /// rule refuses the OS-owned ⌘Q/W/H/M/Space/Tab (and ⇧⌘3–6) so a registration
    /// cannot swallow them, and accepts bare F1–F20 because function keys do not
    /// collide with typing. A Shift-only chord is still ordinary text.
    var isValid: Bool { enabled && combo.isUsableGlobalHotkey }

    /// The modifier glyphs in canonical macOS order (⌃⌥⇧⌘).
    var modifierSymbols: String { combo.modifiers.symbols }

    /// Uses the recorder's key naming so the panel hint matches it.
    var displayString: String { combo.displayString }

    // MARK: Persistence

    /// Decodes a binding from its stored JSON string, or returns `fallback`.
    static func decode(_ json: String?, fallback: HotkeyBinding) -> HotkeyBinding {
        guard let json, let data = json.data(using: .utf8),
              let value = try? JSONDecoder().decode(HotkeyBinding.self, from: data) else { return fallback }
        return value
    }

    /// Encodes the binding to a JSON string for `UserDefaults`.
    var jsonString: String {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
    }

    // MARK: Defaults

    /// Summon / dismiss the research panel. ⌃⌥⌘Space — three modifiers, so it can't
    /// collide with Spotlight (⌘Space) or an input-source switch (⌃Space).
    static let defaultSummon = HotkeyBinding(keyCode: UInt32(kVK_Space),
                                             modifiers: UInt32(controlKey | optionKey | cmdKey),
                                             keyLabel: "Space", enabled: true)

    /// Summon the panel *and* seed the composer with the frontmost app's selected
    /// text. Off by default: it is the one path that needs Accessibility, so the
    /// user opts in from Settings ▸ Shortcuts rather than being prompted at launch.
    static let defaultResearchSelection = HotkeyBinding(keyCode: UInt32(kVK_ANSI_J),
                                                        modifiers: UInt32(controlKey | optionKey | cmdKey),
                                                        keyLabel: "J", enabled: false)
}
