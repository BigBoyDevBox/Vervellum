#if os(Linux)
import XCTest
@testable import VervellumKit

final class LinuxPanelTests: XCTestCase {

    /// The shared text-scale preference reaches the GTK thread through one CSS rule.
    func testTheStylesheetScalesTheThread() {
        XCTAssertTrue(LinuxPanel.stylesheet(textScale: 1.0).contains(".thread { font-size: 1.00em; }"))
        XCTAssertTrue(LinuxPanel.stylesheet(textScale: 1.25).contains(".thread { font-size: 1.25em; }"))
        // The rest of the sheet survives the scaling rule.
        XCTAssertTrue(LinuxPanel.stylesheet(textScale: 1.0).contains(".composer {"))
    }

    /// `/copy` copies the last real question's transcript, never the notice a
    /// previous command printed — a notice turn has no question.
    func testCopyTakesTheLastRealAnswerNotAPanelNotice() {
        var answered = ResearchTurn(question: "What is the state?")
        answered.stage = .complete
        answered.answer = "Settled [1]."
        var notice = ResearchTurn(question: "")
        notice.stage = .complete
        notice.answer = "Copied the answer."
        var thread = ResearchThread()
        thread.turns = [answered, notice]

        XCTAssertEqual(LinuxPanel.turnToCopy(in: thread)?.answer, "Settled [1].")
        XCTAssertNil(LinuxPanel.turnToCopy(in: ResearchThread()))
    }

    func testPasteInterceptionUsesTheLayoutNeutralShortcutMatch() {
        XCTAssertTrue(GTK.shouldInterceptPaste(shortcutMatches: true,
                                               controlPressed: true,
                                               shiftPressed: false))
        XCTAssertFalse(GTK.shouldInterceptPaste(shortcutMatches: false,
                                                controlPressed: true,
                                                shiftPressed: false))
        XCTAssertFalse(GTK.shouldInterceptPaste(shortcutMatches: true,
                                                controlPressed: true,
                                                shiftPressed: true))
    }
}
#endif
