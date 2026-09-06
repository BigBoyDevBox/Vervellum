import XCTest
@testable import Vervellum

final class PanelPlacementTests: XCTestCase {

    /// A 16-inch laptop's visible frame: not at the origin, and shorter than the
    /// screen because of the menu bar.
    private let visible = CGRect(x: 0, y: 0, width: 1728, height: 1080 - 38)

    func testTrailingSitsAgainstTheRightEdge() {
        let frame = PanelPlacement.frame(in: visible, side: .trailing, width: 460)
        XCTAssertEqual(frame.maxX, visible.maxX - PanelPlacement.margin, accuracy: 0.01)
        XCTAssertEqual(frame.width, 460, accuracy: 0.01)
    }

    func testLeadingSitsAgainstTheLeftEdge() {
        let frame = PanelPlacement.frame(in: visible, side: .leading, width: 460)
        XCTAssertEqual(frame.minX, visible.minX + PanelPlacement.margin, accuracy: 0.01)
    }

    func testEdgeLayoutsFillTheVisibleHeight() {
        let frame = PanelPlacement.frame(in: visible, side: .trailing)
        XCTAssertEqual(frame.height, visible.height - PanelPlacement.margin * 2, accuracy: 0.01)
    }

    func testCenteredIsHorizontallyCentredAndAboveTheMiddle() {
        let frame = PanelPlacement.frame(in: visible, side: .center, width: 460, height: 620)
        XCTAssertEqual(frame.midX, visible.midX, accuracy: 0.01)
        XCTAssertEqual(frame.height, 620, accuracy: 0.01)
        XCTAssertGreaterThan(frame.midY, visible.midY)
    }

    /// A remembered width from a 6K display must not strand the panel off the edge of
    /// a laptop screen.
    func testWidthIsClampedToTheScreen() {
        let narrow = CGRect(x: 0, y: 0, width: 500, height: 800)
        let frame = PanelPlacement.frame(in: narrow, side: .trailing, width: 2000)
        XCTAssertLessThanOrEqual(frame.width, narrow.width - PanelPlacement.margin * 2)
        XCTAssertTrue(narrow.contains(frame))
    }

    func testWidthIsClampedToTheSupportedRange() {
        let tiny = PanelPlacement.frame(in: visible, side: .trailing, width: 10)
        XCTAssertEqual(tiny.width, PanelPlacement.minimumWidth, accuracy: 0.01)
        let huge = PanelPlacement.frame(in: visible, side: .trailing, width: 9000)
        XCTAssertEqual(huge.width, PanelPlacement.maximumWidth, accuracy: 0.01)
    }

    func testCenteredHeightIsClampedToTheScreen() {
        let short = CGRect(x: 0, y: 0, width: 1440, height: 400)
        let frame = PanelPlacement.frame(in: short, side: .center, width: 460, height: 2000)
        XCTAssertTrue(short.contains(frame))
    }

    /// A display waking up can report a zero-size frame; a negative-size window would
    /// be a crash rather than a layout glitch.
    func testDegenerateScreenDoesNotProduceANegativeSizeFrame() {
        for side in PanelSide.allCases {
            let frame = PanelPlacement.frame(in: .zero, side: side)
            XCTAssertGreaterThanOrEqual(frame.width, 0)
            XCTAssertGreaterThanOrEqual(frame.height, 0)
        }
    }

    func testRespectsANonZeroScreenOrigin() {
        let secondary = CGRect(x: 1728, y: -200, width: 1920, height: 1080)
        let frame = PanelPlacement.frame(in: secondary, side: .trailing, width: 460)
        XCTAssertTrue(secondary.contains(frame))
    }

    func testEntryFrameOffsetsTowardsTheAnchoringEdge() {
        let frame = CGRect(x: 100, y: 100, width: 400, height: 600)
        XCTAssertLessThan(PanelPlacement.entryFrame(for: frame, side: .leading).minX, frame.minX)
        XCTAssertGreaterThan(PanelPlacement.entryFrame(for: frame, side: .trailing).minX, frame.minX)
        XCTAssertLessThan(PanelPlacement.entryFrame(for: frame, side: .center).minY, frame.minY)
    }
}
