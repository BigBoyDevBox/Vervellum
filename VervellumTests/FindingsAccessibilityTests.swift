import AppKit
import SwiftUI
import XCTest
@testable import Vervellum

/// The citation chips inside a finding must stay individually reachable.
///
/// `.accessibilityElement(children: .combine)` collapsed each finding row into one
/// static element and took the chips' actions with it, so a VoiceOver reader could see
/// the combined summary but could not open the source the chip names — the same source
/// is in the list under the answer, but the chip itself had stopped existing as an
/// element. This is the same tree-walking check the history rows use.
@MainActor
final class FindingsAccessibilityTests: XCTestCase {

    func testCitationChipsRemainAccessibleActions() throws {
        let source = Source(number: 1, url: "https://a.example/one", title: "One", snippet: "")
        let finding = Finding(claim: "The page says what the answer claims.",
                              verdict: .supported,
                              reasoning: "It states it directly.",
                              sourceNumbers: [1])

        let hosting = NSHostingView(rootView:
            FindingsView(findings: [finding], sources: [source], onSelectSource: { _ in }))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }

        let laidOut = expectation(description: "Findings laid out")
        DispatchQueue.main.async { laidOut.fulfill() }
        wait(for: [laidOut], timeout: 3)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertTrue(labels(in: hosting).contains("Source 1, a.example"),
                      "the chip must survive as its own element with its own label")
    }

    private func labels(in element: Any) -> [String] {
        guard let accessible = element as? NSAccessibility else { return [] }
        let own = accessible.accessibilityLabel().map { [$0] } ?? []
        return own + (accessible.accessibilityChildren() ?? []).flatMap { labels(in: $0) }
    }
}
