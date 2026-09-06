import XCTest
import Carbon.HIToolbox
@testable import Vervellum

final class HotkeyBindingTests: XCTestCase {

    func testDefaultsAreValidAndDisplayCorrectly() {
        XCTAssertTrue(HotkeyBinding.defaultSummon.isValid)
        XCTAssertEqual(HotkeyBinding.defaultSummon.displayString, "⌃⌥⌘Space")
        XCTAssertEqual(HotkeyBinding.defaultResearchSelection.displayString, "⌃⌥⌘J")
    }

    /// The selection shortcut is the only feature needing Accessibility, so it is
    /// off until the user opts in.
    func testTheSelectionShortcutIsDisabledByDefault() {
        XCTAssertFalse(HotkeyBinding.defaultResearchSelection.enabled)
        XCTAssertFalse(HotkeyBinding.defaultResearchSelection.isValid)
    }

    func testModifierSymbolsAreInCanonicalOrder() {
        let binding = HotkeyBinding(keyCode: 0,
                                    modifiers: UInt32(cmdKey | controlKey | optionKey | shiftKey),
                                    keyLabel: "A", enabled: true)
        XCTAssertEqual(binding.modifierSymbols, "⌃⌥⇧⌘")
    }

    /// A bare key would be captured system-wide, so it is never registerable.
    func testIsInvalidWithoutModifiersOrWhenDisabled() {
        XCTAssertFalse(HotkeyBinding(keyCode: 1, modifiers: 0, keyLabel: "S", enabled: true).isValid)
        XCTAssertFalse(HotkeyBinding(keyCode: 2, modifiers: UInt32(cmdKey),
                                     keyLabel: "D", enabled: false).isValid)
    }

    func testJSONRoundTrip() {
        let original = HotkeyBinding(keyCode: 49, modifiers: UInt32(cmdKey | optionKey),
                                     keyLabel: "Space", enabled: true)
        XCTAssertEqual(HotkeyBinding.decode(original.jsonString, fallback: .defaultSummon), original)
    }

    func testDecodeFallsBackOnGarbage() {
        XCTAssertEqual(HotkeyBinding.decode("not json", fallback: .defaultSummon), .defaultSummon)
        XCTAssertEqual(HotkeyBinding.decode(nil, fallback: .defaultSummon), .defaultSummon)
    }

    func testCarbonModifiersMapping() {
        let modifiers = HotkeyBinding.carbonModifiers(from: [.command, .shift])
        XCTAssertEqual(modifiers & UInt32(cmdKey), UInt32(cmdKey))
        XCTAssertEqual(modifiers & UInt32(shiftKey), UInt32(shiftKey))
        XCTAssertEqual(modifiers & UInt32(controlKey), 0)
        XCTAssertEqual(modifiers & UInt32(optionKey), 0)
    }
}
