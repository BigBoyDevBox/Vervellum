import Foundation
import XCTest
#if canImport(VervellumKit)
// Linux: the portable code is its own SwiftPM module.
@testable import VervellumKit
#else
// macOS: it is compiled straight into the app target, so there is no separate module.
@testable import Vervellum
#endif

/// `ResearchSession` owns a thread's run state. These tests give it a `hop` that
/// *queues* the runner's callbacks instead of delivering them, so the order in which
/// cancel, discard and a finishing run interleave is chosen by the test rather than
/// by the cooperative pool's scheduler. No run touches the network: an empty
/// configuration fails before the first request is attempted.
final class ResearchSessionTests: XCTestCase {

    private func makeSession(
        hop: @escaping (@escaping () -> Void) -> Void = { $0() }
    ) -> ResearchSession {
        ResearchSession(thread: ResearchThread(),
                        preferences: CorePreferences(store: MemorySettingsStore()),
                        secrets: EphemeralSecretStore(),
                        logSink: SilentLog(),
                        hop: hop)
    }

    /// A `hop` that enqueues callbacks rather than running them. The semaphore
    /// signals each enqueue, so a test can wait until the runner has reported and
    /// then deliver the callbacks by hand.
    private final class HopQueue {
        private var work: [() -> Void] = []
        private let lock = NSLock()
        private let semaphore = DispatchSemaphore(value: 0)

        var hop: (@escaping () -> Void) -> Void {
            { [self] block in
                self.lock.lock()
                self.work.append(block)
                self.lock.unlock()
                self.semaphore.signal()
            }
        }

        /// Waits for `count` runner callbacks to be enqueued.
        func expect(_ count: Int, file: StaticString = #filePath, line: UInt = #line) {
            for _ in 0..<count {
                XCTAssertEqual(semaphore.wait(timeout: .now() + 5), .success,
                               "timed out waiting for a runner callback",
                               file: file, line: line)
            }
        }

        /// Delivers everything enqueued so far.
        func drain() {
            lock.lock()
            let pending = work
            work.removeAll()
            lock.unlock()
            pending.forEach { $0() }
        }
    }

    func testAnUnconfiguredAskFailsTheTurn() {
        let hops = HopQueue()
        let session = makeSession(hop: hops.hop)
        var persists = 0
        session.onPersist = { _ in persists += 1 }

        session.ask("question")
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(persists, 1)

        // Two reports are enqueued for a failed run: the snapshot carrying the
        // failed stage, then `finish`.
        hops.expect(2)
        hops.drain()

        XCTAssertEqual(session.thread.turns.count, 1)
        XCTAssertEqual(session.thread.turns.first?.stage, .failed)
        XCTAssertNotNil(session.thread.turns.first?.failure)
        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(persists, 2)
    }

    func testAWhileRunningAskIsIgnored() {
        let hops = HopQueue()
        let session = makeSession(hop: hops.hop)

        session.ask("first")
        session.ask("second")

        XCTAssertEqual(session.thread.turns.count, 1)
        XCTAssertEqual(session.thread.turns.first?.question, "first")
        session.discard()
    }

    func testDiscardStopsTheRunAndSealsPersistence() {
        let hops = HopQueue()
        let session = makeSession(hop: hops.hop)
        var persists = 0
        session.onPersist = { _ in persists += 1 }

        session.ask("question")
        session.discard()

        XCTAssertFalse(session.isRunning)
        XCTAssertTrue(session.isDiscarded)

        hops.expect(2)
        hops.drain()

        // The run's last snapshot still lands on the turn — cancelled or failed,
        // whichever the task observed first — but nothing about a discarded thread
        // is persisted again. Re-saving is what would resurrect a deleted thread.
        XCTAssertTrue(session.thread.turns.first?.stage.isTerminal ?? false)
        XCTAssertEqual(persists, 1)
    }

    func testCancelOnAnIdleSessionIsQuiet() {
        let session = makeSession()
        var persists = 0
        session.onPersist = { _ in persists += 1 }

        session.cancel()

        XCTAssertFalse(session.isRunning)
        XCTAssertEqual(persists, 0)
    }

    func testRetryReAsksAFailedTurn() {
        let hops = HopQueue()
        let session = makeSession(hop: hops.hop)
        session.ask("question")
        hops.expect(2)
        hops.drain()

        let failedID = session.thread.turns[0].id
        session.retry(failedID)

        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(session.thread.turns.count, 1)
        XCTAssertNotEqual(session.thread.turns[0].id, failedID)
        session.discard()
    }

    func testLocalTurnsRenderButAreNotPersisted() {
        let session = makeSession()
        var structural = 0
        session.onMutate = { _, mutation in
            if mutation.isStructural { structural += 1 }
        }

        var notice = ResearchTurn(question: "")
        notice.answer = "help text"
        notice.stage = .complete
        session.appendLocalTurn(notice)

        XCTAssertEqual(session.thread.turns.count, 1)
        XCTAssertEqual(structural, 1)
        XCTAssertTrue(session.persistableThread.turns.isEmpty)
    }

    /// The property the whole feature rests on: one session's lifecycle says nothing
    /// about another's.
    func testDetachedSessionsRunIndependently() {
        let hopsA = HopQueue()
        let hopsB = HopQueue()
        let sessionA = makeSession(hop: hopsA.hop)
        let sessionB = makeSession(hop: hopsB.hop)
        var persistsA = 0
        var persistsB = 0
        sessionA.onPersist = { _ in persistsA += 1 }
        sessionB.onPersist = { _ in persistsB += 1 }

        sessionA.ask("first thread")
        sessionB.ask("second thread")
        XCTAssertTrue(sessionA.isRunning)
        XCTAssertTrue(sessionB.isRunning)

        // Finishing A's run leaves B's untouched.
        hopsA.expect(2)
        hopsA.drain()
        XCTAssertFalse(sessionA.isRunning)
        XCTAssertTrue(sessionB.isRunning)
        XCTAssertEqual(persistsA, 2)
        XCTAssertEqual(persistsB, 1)

        sessionB.discard()
        hopsB.expect(2)
        hopsB.drain()
        XCTAssertEqual(persistsB, 1)
    }
}
