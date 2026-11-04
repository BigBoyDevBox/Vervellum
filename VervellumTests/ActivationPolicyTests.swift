import AppKit
import XCTest
@testable import Vervellum

final class ActivationPolicyTests: XCTestCase {

    func testRestoringActivationDoesNotRaiseEveryWindow() {
        XCTAssertTrue(NSApplication.vervellumRestoreActivationOptions.isEmpty)
        XCTAssertFalse(NSApplication.vervellumRestoreActivationOptions.contains(.activateAllWindows))
    }
}
