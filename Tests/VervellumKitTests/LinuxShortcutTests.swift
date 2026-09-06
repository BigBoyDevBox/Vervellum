#if os(Linux)
import XCTest
@testable import VervellumKit

/// The GVariant list handling in `ShortcutInstaller`.
///
/// Worth its own tests because the shape `gsettings` prints for an *empty* list is
/// `@as []`, not `[]` — and the obvious string append produces `@as [, 'x']`, which is
/// invalid GVariant and is rejected on write. Getting this wrong silently fails to
/// install the shortcut, or worse, clobbers another application's binding.
final class LinuxShortcutTests: XCTestCase {

    func testParsesAnEmptyList() {
        XCTAssertEqual(ShortcutInstaller.paths(in: "@as []"), [])
        XCTAssertEqual(ShortcutInstaller.paths(in: "[]"), [])
    }

    func testParsesOneAndSeveralEntries() {
        let base = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings"
        XCTAssertEqual(ShortcutInstaller.paths(in: "['\(base)/custom0/']"), ["\(base)/custom0/"])
        XCTAssertEqual(
            ShortcutInstaller.paths(in: "['\(base)/custom0/', '\(base)/custom3/']"),
            ["\(base)/custom0/", "\(base)/custom3/"])
    }

    func testEncodesTheEmptyListAsGVariantExpectsIt() {
        XCTAssertEqual(ShortcutInstaller.encode([]), "@as []")
    }

    func testEncodingRoundTrips() {
        let paths = ["/a/custom0/", "/a/custom1/"]
        XCTAssertEqual(ShortcutInstaller.paths(in: ShortcutInstaller.encode(paths)), paths)
    }

    /// Appending must never lose an entry another application owns.
    func testAppendingPreservesExistingEntries() {
        let existing = ShortcutInstaller.paths(in: "['/a/custom0/']")
        let combined = ShortcutInstaller.encode(existing + ["/a/custom1/"])
        XCTAssertEqual(ShortcutInstaller.paths(in: combined), ["/a/custom0/", "/a/custom1/"])
    }

    func testTheShortcutCommandTargetsTheRunningInstance() {
        XCTAssertEqual(ShortcutInstaller.command, "gapplication action ch.lkmc.Vervellum toggle")
    }
}

/// XDG path resolution, which Foundation gets wrong on Linux.
final class LinuxPathsTests: XCTestCase {

    func testPathsAreNamespacedUnderTheApplication() {
        XCTAssertTrue(LinuxPaths.settingsFile.path.hasSuffix("/vervellum/settings.json"))
        XCTAssertTrue(LinuxPaths.threadsFile.path.hasSuffix("/vervellum/threads.json"))
    }

    func testConfigAndDataAreSeparate() {
        XCTAssertNotEqual(LinuxPaths.configDirectory, LinuxPaths.dataDirectory)
    }
}
#endif
