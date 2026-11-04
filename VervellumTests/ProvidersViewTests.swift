import AppKit
import SwiftUI
import XCTest
@testable import Vervellum

final class ProvidersViewTests: XCTestCase {

    func testClearIsCancelledWhenSettingsClosesWithoutSave() throws {
        if Thread.isMainThread {
            try exercisePendingClear()
        } else {
            try DispatchQueue.main.sync { try exercisePendingClear() }
        }
    }

    private func exercisePendingClear() throws {
        let suite = "VervellumProvidersViewTest-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let preferences = Preferences(defaults: defaults)
        let id = UUID()
        let account = SecretAccount.derived(from: .modelAPIKey, for: id)
        preferences.core.providerSettings = ProviderSettings(
            modelProfiles: [ModelProfile(
                id: id, name: "Test", endpoint: "https://model.example/v1",
                model: "test-model", keyAccount: account.rawValue)],
            selectedModelID: id,
            searchProfiles: [])
        let secrets = RecordingProvidersSecretStore([account: "stored key"])

        let first = host(preferences: preferences, secrets: secrets)
        defer { first.window.close() }
        settle(first.hosting)
        let field = try XCTUnwrap(secureField(in: first.hosting))
        let storedWidth = field.bounds.width

        try clickClear(beside: field, in: first.window)
        settle(first.hosting)

        XCTAssertGreaterThan(field.bounds.width, storedWidth + 20,
                             "Clear should become a pending form edit and hide its button")
        XCTAssertTrue(secrets.mutations.isEmpty,
                      "closing an unsaved form must not have touched the Keychain")
        XCTAssertEqual(secrets.value(for: account), "stored key")

        first.window.close()
        let reopened = host(preferences: preferences, secrets: secrets)
        defer { reopened.window.close() }
        settle(reopened.hosting)
        let reopenedField = try XCTUnwrap(secureField(in: reopened.hosting))

        XCTAssertEqual(reopenedField.bounds.width, storedWidth, accuracy: 1,
                       "a fresh Settings view must rediscover the still-stored key")
        XCTAssertTrue(secrets.mutations.isEmpty)
    }

    private func host(preferences: Preferences, secrets: SecretStore)
        -> (window: NSWindow, hosting: NSHostingView<ProvidersView>) {
        let hosting = NSHostingView(rootView: ProvidersView(
            preferences: preferences, keychain: secrets))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 700, height: 900),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        return (window, hosting)
    }

    private func settle(_ view: NSView) {
        view.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.1))
        view.layoutSubtreeIfNeeded()
    }

    private func secureField(in view: NSView) -> NSSecureTextField? {
        if let field = view as? NSSecureTextField { return field }
        return view.subviews.lazy.compactMap(secureField).first
    }

    private func clickClear(beside field: NSSecureTextField,
                            in window: NSWindow) throws {
        // The field's rect is converted all the way to screen coordinates —
        // convert(_, to: nil) reaches the window's coordinate system and
        // convertToScreen finishes the trip — because the button's accessibility
        // frame is measured in that same global space.
        let fieldRect = window.convertToScreen(field.convert(field.bounds, to: nil))
        let button = try XCTUnwrap(clearButton(beside: fieldRect),
                                   "no Clear button beside the key field")
        // A synthesized click never reaches the button here: the test host stays
        // an inactive app, and both window.sendEvent and a posted CGEvent are
        // swallowed as first-mouse before SwiftUI sees a press. Pressing through
        // the accessibility element the button was located as is reliable.
        XCTAssertEqual(AXUIElementPerformAction(button, kAXPressAction as CFString),
                       .success)
    }

    /// The accessibility element for the Clear button on the field's own row.
    /// This OS renders SwiftUI's buttons without an NSButton to click — hits are
    /// answered inside the hosting view — so the button is located through the
    /// accessibility tree by role and label rather than assumed to sit a fixed
    /// offset past the field.
    private func clearButton(beside fieldRect: NSRect) -> AXUIElement? {
        var found: [AXUIElement] = []
        let app = AXUIElementCreateApplication(ProcessInfo.processInfo.processIdentifier)
        for element in attribute(kAXWindowsAttribute, of: app) as? [AXUIElement] ?? [] {
            collectClearButtons(in: element, into: &found)
        }
        // More than one key row can offer Clear at once; the field's own row is
        // the one nearest to its middle. `fieldRect` is a Cocoa screen rect —
        // measured up from the bottom, where AX measures down — so the AX frames
        // are flipped before comparing distances.
        let height = mainScreenHeight
        return found.min { lhs, rhs in
            distance(from: axFrame(of: lhs), to: fieldRect, screenHeight: height)
                < distance(from: axFrame(of: rhs), to: fieldRect, screenHeight: height)
        }
    }

    private func collectClearButtons(in element: AXUIElement,
                                     into found: inout [AXUIElement]) {
        if attribute(kAXRoleAttribute, of: element) as? String == kAXButtonRole as String,
           [kAXTitleAttribute, kAXDescriptionAttribute]
               .contains(where: { attribute($0, of: element) as? String == "Clear" }) {
            found.append(element)
        }
        for child in attribute(kAXChildrenAttribute, of: element) as? [AXUIElement] ?? [] {
            collectClearButtons(in: child, into: &found)
        }
    }

    private func attribute(_ name: String, of element: AXUIElement) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success
        else { return nil }
        return value
    }

    private func axFrame(of element: AXUIElement) -> NSRect? {
        var position = CGPoint.zero
        var size = CGSize.zero
        guard let positionValue = attribute(kAXPositionAttribute, of: element),
              let sizeValue = attribute(kAXSizeAttribute, of: element),
              AXValueGetValue(positionValue as! AXValue, .cgPoint, &position),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        else { return nil }
        return NSRect(origin: position, size: size)
    }

    private var mainScreenHeight: CGFloat { NSScreen.screens.first?.frame.height ?? 0 }

    /// Between an AX-space frame and a Cocoa screen-space rect: the AX midpoint is
    /// flipped into Cocoa space before the comparison.
    private func distance(from axRect: NSRect?, to cocoaRect: NSRect,
                          screenHeight: CGFloat) -> CGFloat {
        guard let axRect else { return .greatestFiniteMagnitude }
        return hypot(axRect.midX - cocoaRect.midX,
                     (screenHeight - axRect.midY) - cocoaRect.midY)
    }
}

private final class RecordingProvidersSecretStore: SecretStore {
    private var values: [SecretAccount: String]
    private(set) var mutations: [String] = []

    init(_ values: [SecretAccount: String]) { self.values = values }

    var backendDescription: String { "test store" }
    func value(for account: SecretAccount) -> String? { values[account] }

    func set(_ secret: String, for account: SecretAccount) throws {
        mutations.append("set:\(account.rawValue)")
        values[account] = secret
    }

    func delete(_ account: SecretAccount) throws {
        mutations.append("delete:\(account.rawValue)")
        values[account] = nil
    }
}
