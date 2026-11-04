import AppKit
import SwiftUI
import XCTest
@testable import Vervellum

/// The delete action in a history row must work without the pointer hovering it.
///
/// The trash used to appear only while the row was hovered, so keyboard and VoiceOver
/// users had no way to delete a thread. The accessibility tree of a hosted SwiftUI view
/// is empty in a test process, so this drives the real control with local mouse events
/// that never produce a hover, and checks the click reaches Delete and not Open.
@MainActor
final class HistoryAccessibilityTests: XCTestCase {
    func testDeleteWorksWithoutPointerHover() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = ThreadStore(fileURL: directory.appendingPathComponent("threads.json"))
        var thread = ResearchThread()
        var turn = ResearchTurn(question: "A research question")
        turn.stage = .complete
        thread.turns = [turn]
        store.save(thread)
        store.flush()
        var deleted = 0
        var opened = 0
        let hosting = NSHostingView(rootView: HistoryView(store: store,
            onOpen: { _ in opened += 1 }, onDelete: { _ in deleted += 1 }, onClose: {}))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 240),
                              styleMask: .titled, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }
        settle()
        hosting.layoutSubtreeIfNeeded()

        // Fixed fixture: trailing action in the first row, below the search field.
        // These local events do not move the pointer or send a hover event.
        let deletePoint = NSPoint(x: 380, y: 190)
        for (number, type) in [NSEvent.EventType.leftMouseDown, .leftMouseUp].enumerated() {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: deletePoint,
                modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber, context: nil, eventNumber: number,
                clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        settle()
        XCTAssertEqual(deleted, 1)
        XCTAssertEqual(opened, 0, "Delete must not activate Open")
    }

    private func settle() {
        let laidOut = expectation(description: "History event loop settled")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { laidOut.fulfill() }
        wait(for: [laidOut], timeout: 3)
    }
}
