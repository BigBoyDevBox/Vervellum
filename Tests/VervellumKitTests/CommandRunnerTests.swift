import XCTest
#if canImport(VervellumKit)
@testable import VervellumKit
#else
@testable import Vervellum
#endif

final class CommandRunnerTests: XCTestCase {

    private let runner = CommandRunner()
    private let environment = [
        "HOME": NSHomeDirectory(),
        "PATH": "/usr/bin:/bin",
        "LANG": "C",
    ]

    private func run(_ executable: String, _ arguments: [String],
                     limit: Int = 512 * 1024, timeout: TimeInterval = 5)
        async throws -> (status: Int32, output: Data) {
        try await runner.run(executable: URL(fileURLWithPath: executable),
                             arguments: arguments, environment: environment,
                             limit: limit, timeout: timeout)
    }

    /// The direct command owns the result. A grandchild can inherit stdout, but it
    /// cannot keep a completed search parked until that unrelated process exits.
    func testReturnsWhenADescendantKeepsStandardOutputOpen() async throws {
        let began = Date()

        let result = try await run(
            "/bin/sh", ["-c", "/bin/sleep 2 & printf ready"], timeout: 4)

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(String(data: result.output, encoding: .utf8), "ready")
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.25,
                          "the direct shell exited; its sleeping child only inherited the pipe")
    }

    /// Ending on direct-child exit must still drain everything the child put in the
    /// pipe. This is deliberately several read chunks with a distinctive final tail.
    func testDrainsBufferedOutputBeforeReturning() async throws {
        let count = 200_000
        let program = "BEGIN { for (i = 0; i < \(count); i++) printf \"x\"; printf \"TAIL\" }"

        let result = try await run("/usr/bin/awk", [program])

        XCTAssertEqual(result.status, 0)
        XCTAssertEqual(result.output.count, count + 4)
        XCTAssertTrue(result.output.suffix(4).elementsEqual(Data("TAIL".utf8)))
    }

    func testOutputLimitStillWinsWhenTheChildExits() async throws {
        do {
            _ = try await run("/usr/bin/awk", [
                "BEGIN { for (i = 0; i < 1025; i++) printf \"x\" }",
            ], limit: 1024)
            XCTFail("Expected the output limit")
        } catch let error as ResearchError {
            XCTAssertTrue(error.message.contains("printed more than 1 KB"), error.message)
        }
    }

    func testTimeoutStopsAStillRunningCommand() async throws {
        let began = Date()
        do {
            _ = try await run("/bin/sleep", ["5"], timeout: 0.1)
            XCTFail("Expected a timeout")
        } catch let error as ResearchError {
            XCTAssertTrue(error.message.contains("did not finish"), error.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.5)
    }

    /// A zero status is not success when it was produced by handling Vervellum's
    /// timeout signal. Only a process already stopped when the deadline checks may win
    /// the natural-exit race.
    func testTimeoutDoesNotForgiveAChildThatHandlesTERMAndExitsZero() async throws {
        let began = Date()
        do {
            _ = try await run(
                "/bin/sh",
                ["-c", "trap 'exit 0' TERM; while :; do sleep 1; done"],
                timeout: 0.1)
            XCTFail("Expected a timeout")
        } catch let error as ResearchError {
            XCTAssertTrue(error.message.contains("did not finish"), error.message)
        }
        XCTAssertLessThan(Date().timeIntervalSince(began), 1.5)
    }

    /// SIGTERM is only a request. The runner must answer after its bounded grace even
    /// when the direct child deliberately ignores that request.
    func testTimeoutEscalatesWhenTheChildIgnoresTERM() async throws {
        let began = Date()
        do {
            _ = try await run(
                "/bin/sh", ["-c", "trap '' TERM; exec /bin/sleep 5"], timeout: 0.1)
            XCTFail("Expected a timeout")
        } catch let error as ResearchError {
            XCTAssertTrue(error.message.contains("did not finish"), error.message)
        }
        let elapsed = Date().timeIntervalSince(began)
        XCTAssertGreaterThanOrEqual(elapsed, CommandRunner.terminationGrace)
        XCTAssertLessThan(elapsed, CommandRunner.terminationGrace + 1.5)
    }

    func testCancellationStopsAStillRunningCommand() async throws {
        let task = Task {
            try await self.run("/bin/sleep", ["5"], timeout: 10)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected cancellation")
        } catch let error as ResearchError {
            XCTAssertEqual(error, .cancelled)
        }
    }

    func testReturnsNonzeroStatusAndCapturedOutput() async throws {
        let result = try await run("/bin/sh", ["-c", "printf failed; exit 7"])

        XCTAssertEqual(result.status, 7)
        XCTAssertEqual(String(data: result.output, encoding: .utf8), "failed")
    }

    func testLaunchFailureUsesAnApplicationWrittenMessage() async throws {
        do {
            _ = try await run("/definitely/not/a/program", [])
            XCTFail("Expected a launch failure")
        } catch let error as ResearchError {
            XCTAssertEqual(error.message,
                           "Vervellum could not start the search command. Check the "
                            + "command in the provider settings.")
        }
    }
}
