import AppKit
import SwiftUI
import XCTest
@testable import Vervellum

@MainActor
final class ComposerAccessibilityTests: XCTestCase {
    func testNativeComposerHasAnAccessibleQuestionLabel() throws {
        let placeholder = "Ask a follow-up"
        let composer = ComposerView(text: .constant(""), placeholder: placeholder,
                                    submitOnReturn: true, onSubmit: {}, attachmentCount: 0,
                                    onAttach: { _ in })
        let hosting = NSHostingView(rootView: composer)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 320, height: 80),
                              styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFront(nil)
        defer { window.close() }

        let laidOut = expectation(description: "Composer laid out")
        DispatchQueue.main.async { laidOut.fulfill() }
        wait(for: [laidOut], timeout: 3)
        hosting.layoutSubtreeIfNeeded()

        let field = try XCTUnwrap(textView(in: hosting))
        XCTAssertEqual(field.accessibilityLabel(), "Question")
        XCTAssertEqual(field.accessibilityHelp(), placeholder)
    }

    private func textView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { self.textView(in: $0) }.first
    }
}
