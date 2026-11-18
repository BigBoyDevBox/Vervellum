import XCTest
import AppKit
import Carbon.HIToolbox
import KeycapCore
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

    /// A disabled binding is never registerable, and so is a bare or Shift-only
    /// key: Shift-A is ordinary text and must not be captured system-wide.
    func testIsInvalidWithoutUsableModifiersOrWhenDisabled() {
        XCTAssertFalse(HotkeyBinding(keyCode: 1, modifiers: 0, keyLabel: "S", enabled: true).isValid)
        XCTAssertFalse(HotkeyBinding(keyCode: 2, modifiers: UInt32(cmdKey),
                                     keyLabel: "D", enabled: false).isValid)

        let shifted = HotkeyBinding(keyCode: 0, modifiers: UInt32(shiftKey),
                                    keyLabel: "A", enabled: true)
        XCTAssertFalse(shifted.isValid)

        let alphaLock = HotkeyBinding(keyCode: 0, modifiers: UInt32(alphaLock),
                                      keyLabel: "A", enabled: true)
        XCTAssertFalse(alphaLock.isValid)
    }

    /// Keycap's family rule: the OS-owned ⌘Q/W/H/M/Space/Tab and ⇧⌘3–6 are
    /// refused, so a registration cannot swallow them. Adding ⌥ or ⌃ makes the
    /// same key usable.
    func testReservedCombosAreRefused() {
        let command = UInt32(cmdKey)
        for keyCode in [KeyCode.q, KeyCode.w, KeyCode.h, KeyCode.m, KeyCode.space, KeyCode.tab] {
            XCTAssertFalse(HotkeyBinding(keyCode: keyCode, modifiers: command,
                                         keyLabel: "X", enabled: true).isValid,
                           "⌘\(keyCode) should be refused")
            XCTAssertTrue(HotkeyBinding(keyCode: keyCode, modifiers: command | UInt32(optionKey),
                                        keyLabel: "X", enabled: true).isValid,
                          "⌥⌘\(keyCode) should be usable")
        }
        for keyCode in [KeyCode.three, KeyCode.four, KeyCode.five, KeyCode.six] {
            XCTAssertFalse(HotkeyBinding(keyCode: keyCode,
                                         modifiers: command | UInt32(shiftKey),
                                         keyLabel: "X", enabled: true).isValid,
                           "⇧⌘\(keyCode) should be refused")
        }
    }

    /// Bare function keys are the classic launcher shortcut and never collide
    /// with typing, so they are usable without a modifier.
    func testBareFunctionKeysAreUsable() {
        XCTAssertTrue(HotkeyBinding(keyCode: KeyCode.f5, modifiers: 0,
                                    keyLabel: "F5", enabled: true).isValid)
        XCTAssertTrue(HotkeyBinding(keyCode: KeyCode.f12, modifiers: UInt32(shiftKey),
                                    keyLabel: "F12", enabled: true).isValid)
    }

    /// The recorder converts at the boundary: a binding's combo carries the same
    /// key code and Carbon bits, and rebuilding from it round-trips.
    func testKeyComboConversionRoundTrips() {
        let original = HotkeyBinding(keyCode: 49, modifiers: UInt32(cmdKey | optionKey),
                                     keyLabel: "Space", enabled: true)
        let combo = original.combo
        XCTAssertEqual(combo.keyCode, 49)
        XCTAssertEqual(combo.carbonModifiers, UInt32(cmdKey | optionKey))
        XCTAssertEqual(HotkeyBinding(combo: combo, keyLabel: original.keyLabel,
                                     enabled: original.enabled),
                       original)
    }

    /// Only the four Carbon hotkey bits are part of a registration; caps lock is
    /// dropped on the way into a combo.
    func testComboDropsNonHotkeyModifierBits() {
        let binding = HotkeyBinding(keyCode: 49, modifiers: UInt32(cmdKey | alphaLock),
                                    keyLabel: "Space", enabled: true)
        XCTAssertEqual(binding.combo.carbonModifiers, UInt32(cmdKey))
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
        let modifiers = HotkeyModifiers(carbonFlags: UInt32(cmdKey | shiftKey | alphaLock))
        XCTAssertTrue(modifiers.contains(.command))
        XCTAssertTrue(modifiers.contains(.shift))
        XCTAssertFalse(modifiers.contains(.control))
        XCTAssertFalse(modifiers.contains(.option))
    }
}
