import AppKit
import XCTest
@testable import Vervellum

final class ActivationPolicyTests: XCTestCase {

    func testRestoringActivationDoesNotRaiseEveryWindow() {
        XCTAssertFalse(NSApplication.vervellumRestoreActivationOptions.contains(.activateAllWindows))
    }
}
