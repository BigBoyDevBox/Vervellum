#if os(Linux)
import XCTest
@testable import VervellumKit

final class LinuxDesktopCommandTests: XCTestCase {
    private let python = "/usr/bin/python3"

    func testStubbornCommandExpires() {
        let result = LinuxDesktopCommand.run(python, ["-c",
            "import signal,time; signal.signal(signal.SIGTERM,signal.SIG_IGN); time.sleep(0.3)"],
            timeout: 0.05)
        XCTAssertNil(result)
    }

    func testClosingStdoutDoesNotBypassTheDeadline() {
        let result = LinuxDesktopCommand.run(python, ["-c",
            "import os,time; os.close(1); time.sleep(0.3)"], timeout: 0.05)
        XCTAssertNil(result)
    }

    func testOutputBeyondTheLimitIsRejected() {
        XCTAssertNil(LinuxDesktopCommand.run(python, ["-c", "print('x'*100)"], limit: 8))
    }

    func testInputTravelsThroughStdin() {
        let secret = "not-a-real-key"
        let result = LinuxDesktopCommand.run(python, ["-c",
            "import sys; sys.stdout.write(sys.stdin.read())"], input: secret)
        XCTAssertEqual(result, secret)
    }

    func testInputAndOutputCanMakeProgressTogether() {
        let input = String(repeating: "s", count: 16 * 1024)
        let result = LinuxDesktopCommand.run(python, ["-c",
            "import sys; sys.stdout.write('x'*100000); sys.stdout.flush(); sys.stdout.write(sys.stdin.read())"],
            input: input, limit: 128 * 1024)
        XCTAssertEqual(result, String(repeating: "x", count: 100_000) + input)
    }

    func testEmptyInputReachesEndOfFile() {
        XCTAssertEqual(LinuxDesktopCommand.run(python, ["-c",
            "import sys; sys.stdout.write(sys.stdin.read())"], input: ""), "")
    }

    func testFailedCommandDoesNotReturnForeignErrors() {
        XCTAssertNil(LinuxDesktopCommand.run(python, ["-c",
            "import sys; print('foreign error',file=sys.stderr); sys.exit(1)"]))
    }
}

final class LinuxShortcutInstallationTests: XCTestCase {
    func testAnyFailedWriteRefusesInstallation() {
        for failedWrite in 0..<4 {
            var writes = 0
            let success = ShortcutInstaller.install { arguments in
                if arguments == ["list-schemas"] {
                    return "org.gnome.settings-daemon.plugins.media-keys"
                }
                if arguments.first == "get" { return "@as []" }
                guard arguments.first == "set" else { return nil }
                defer { writes += 1 }
                return writes == failedWrite ? nil : ""
            }
            XCTAssertFalse(success, "write \(failedWrite) failed")
        }
    }

    func testSuccessfulWritesInstallTheShortcut() {
        var writes = 0
        XCTAssertTrue(ShortcutInstaller.install { arguments in
            if arguments == ["list-schemas"] {
                return "org.gnome.settings-daemon.plugins.media-keys"
            }
            if arguments.first == "get" { return "@as []" }
            writes += 1
            return ""
        })
        XCTAssertEqual(writes, 4)
    }
}
#endif
