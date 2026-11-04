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

    /// The in-place repaint admits exactly one shape of change — the same answer plus
    /// more of it — because everything else rebuilds a widget rather than retitling
    /// one. Pinned so a field added to the turn later cannot quietly widen it.
    func testAnswerGrowthIsTheOnlyInPlaceChange() {
        var old = ResearchTurn(question: "What is the state?")
        old.stage = .answering
        old.answer = "First "
        var live = old
        live.answer = "First part [1]."
        XCTAssertTrue(LinuxPanel.isAnswerGrowth(old, live))

        var staged = old
        staged.stage = .assessing
        staged.answer = "First part [1]."
        XCTAssertFalse(LinuxPanel.isAnswerGrowth(old, staged), "a stage move rebuilds")

        var rewritten = old
        rewritten.answer = "Rewritten from scratch."
        XCTAssertFalse(LinuxPanel.isAnswerGrowth(old, rewritten), "a rewrite is not growth")

        var empty = old
        empty.answer = ""
        XCTAssertFalse(LinuxPanel.isAnswerGrowth(empty, live), "the caret step rebuilds")

        var sourced = live
        sourced.sources = [Source(number: 1, url: "https://a.example/1", title: "A", snippet: "")]
        XCTAssertFalse(LinuxPanel.isAnswerGrowth(old, sourced), "a landing source rebuilds")

        // A render with nothing changed (the run ending, a panel-only toggle) must not
        // take the in-place path, which would leave the status line and button stale.
        XCTAssertFalse(LinuxPanel.isAnswerGrowth(live, live), "an unchanged turn rebuilds")
    }
}
#endif
