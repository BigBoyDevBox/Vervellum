import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

final class ComposerCommandTests: XCTestCase {

    func testPlainTextIsAQuestion() {
        XCTAssertEqual(ComposerCommand.parse("  Why is the sky blue?  "),
                       .ask("Why is the sky blue?"))
    }

    func testBlankInputIsNothing() {
        XCTAssertNil(ComposerCommand.parse(""))
        XCTAssertNil(ComposerCommand.parse("   \n "))
    }

    func testParsesKnownCommands() {
        XCTAssertEqual(ComposerCommand.parse("/new"), .newThread)
        XCTAssertEqual(ComposerCommand.parse("/clear"), .newThread)
        XCTAssertEqual(ComposerCommand.parse("/history"), .openHistory)
        XCTAssertEqual(ComposerCommand.parse("/settings"), .openSettings)
        XCTAssertEqual(ComposerCommand.parse("/copy"), .copyLastAnswer)
        XCTAssertEqual(ComposerCommand.parse("/help"), .showHelp)
        XCTAssertEqual(ComposerCommand.parse("/direct what is 2+2"), .direct("what is 2+2"))
    }

    func testCommandsAreCaseInsensitive() {
        XCTAssertEqual(ComposerCommand.parse("/NEW"), .newThread)
        XCTAssertEqual(ComposerCommand.parse("/Direct hi"), .direct("hi"))
    }

    /// The reason parsing is strict: a question that happens to start with a path
    /// must stay a question rather than becoming an unknown-command error.
    func testAnUnknownSlashWordIsPartOfTheQuestion() {
        XCTAssertEqual(ComposerCommand.parse("/etc/hosts is world readable, right?"),
                       .ask("/etc/hosts is world readable, right?"))
        XCTAssertEqual(ComposerCommand.parse("/usr/bin/env"), .ask("/usr/bin/env"))
    }

    /// "/direct" alone is a mode the user is about to type into, not an empty
    /// question — submitting it must do nothing rather than ask a blank question.
    func testBareDirectIsNotSubmittable() {
        XCTAssertNil(ComposerCommand.parse("/direct"))
        XCTAssertNil(ComposerCommand.parse("/direct   "))
    }

    func testCompletionsMatchAPartialCommand() {
        let matches = ComposerCommand.completions(for: "/h")
        XCTAssertEqual(matches?.map(\.name), ["history", "help"])
    }

    func testCompletionsListEverythingForABareSlash() {
        XCTAssertEqual(ComposerCommand.completions(for: "/")?.count, ComposerCommand.catalogue.count)
    }

    func testNoCompletionsOnceAWordFollows() {
        XCTAssertNil(ComposerCommand.completions(for: "/direct what"))
        XCTAssertNil(ComposerCommand.completions(for: "plain question"))
        XCTAssertNil(ComposerCommand.completions(for: "/zzz"))
    }

    func testHelpTextListsEveryCommand() {
        for command in ComposerCommand.catalogue {
            XCTAssertTrue(ComposerCommand.helpText.contains("/\(command.name)"),
                          "help text is missing /\(command.name)")
        }
    }
}
