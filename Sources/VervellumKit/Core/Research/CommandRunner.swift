import Dispatch
import Foundation
// The one platform import under `Core/`, and it is the C library rather than a
// framework: `kill(2)` exists on both platforms and Foundation's `Process` exposes only
// `terminate()`, which sends a signal a program may ignore. See `terminationGrace` for
// what goes wrong without it. On Linux two more C calls work around corelibs-foundation's
// `Process`: `pthread_sigmask(3)` so a child starts with no signals blocked, and
// `waitid(2)` so the direct child's exit is seen when it happens — see
// `launchWithUnblockedSignals` and `pollDirectChild`. Nothing else in this directory
// imports either module, and nothing here uses them for anything else.
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Finding a program on this machine and running it.
///
/// A seam, for the reason `HTTPTransporting` is one. Every other search backend talks
/// to a server, so a stubbed transport can drive a whole research turn in CI; the Kagi
/// backend talks to a program the user installed, and a test that had to install that
/// program would not run in CI at all. Behind this protocol, `KagiCLIClient` is as
/// testable as the HTTP clients — the argument list it builds, the environment it hands
/// over and the JSON it reads back are all assertable without a `kagi` binary existing.
///
/// The protocol is deliberately narrow: **one command, one set of arguments, one
/// environment, output back.** There is no shell, no working directory, no standard
/// input and no way to pass a string that a shell would re-split — see `CommandRunner`
/// for why that is the security property this whole file exists to hold.
protocol CommandRunning: AnyObject {

    /// The executable a command name or path refers to, or nil when there is none.
    ///
    /// Separate from `run` so a missing program is a *configuration* problem, reported
    /// while the provider settings are being validated, rather than a failure in the
    /// middle of a research turn the user is watching.
    func resolve(command: String) -> URL?

    /// Runs `executable` with exactly these arguments and exactly this environment.
    ///
    /// - Parameters:
    ///   - environment: the child's *whole* environment, not a set of additions to this
    ///     process's. See `CommandRunner.run` for why a third-party binary is handed
    ///     what it needs rather than everything Vervellum happens to be holding.
    ///   - limit: the most bytes of standard output to keep. A command that prints more
    ///     than this is stopped and the call fails, rather than a runaway program being
    ///     read into memory until something else breaks.
    ///   - timeout: how long the command may take before it is terminated.
    /// - Returns: the exit status and everything the command wrote to standard output.
    /// - Throws: `ResearchError` when the command could not be started, printed too
    ///   much, ran too long, or was cancelled. A command that ran and *failed* is not
    ///   an error here — it returns its non-zero status, and the caller decides.
    func run(executable: URL,
             arguments: [String],
             environment: [String: String],
             limit: Int,
             timeout: TimeInterval) async throws -> (status: Int32, output: Data)
}

/// Runs a program as a child process.
///
/// **Never through a shell.** `Process` is given an executable and an argument vector,
/// which the kernel passes to the child as separate strings — there is no parsing step
/// in between, so a quote, a semicolon or a backtick inside a search query is a quote, a
/// semicolon or a backtick. This matters more here than it would in a build script: the
/// query is written by a *model*, and in deep research that model has read pages found
/// by an earlier round. A page that could talk the planner into a well-chosen query
/// would, through `/bin/sh -c`, be talking it into a command. There is no code path in
/// this file that builds a command *string*, and there must never be one.
///
/// Three more bounds, none of them optional:
///
/// * **A minimal environment.** The child gets what the caller passes and nothing else.
///   A third-party binary inherits no model key, no reader key, and nothing else this
///   process happens to hold — see `KagiCLIClient.childEnvironment(apiKey:base:)` for
///   what a Kagi search actually needs.
/// * **Standard error goes nowhere.** It is never read, so a provider's own words can
///   never reach a log line or the panel, which is the rule the rest of the research
///   code follows for HTTP errors. It is attached to the null device rather than left
///   unset so that a chatty command cannot fill a pipe nobody is draining and block
///   forever.
/// * **Standard input is the null device**, so a command that decides to prompt reads
///   end-of-file and gives up instead of waiting for a terminal that is not there.
final class CommandRunner: CommandRunning {

    static let shared = CommandRunner()

    /// A concurrent target for the serial queue each invocation owns. Commands may run
    /// beside one another, while one command's pipe, exit, timeout and cancellation
    /// events are ordered against each other.
    private static let queue = DispatchQueue(label: "ch.lkmc.Vervellum.command",
                                             attributes: .concurrent)

    /// Read in chunks rather than to end-of-file: `readDataToEndOfFile` cannot notice
    /// that the output has grown past `limit` until it has already read all of it.
    private static let chunkSize = 64 * 1024

    /// How long a child gets to honour the signal that asks it to stop, before it is
    /// killed.
    ///
    /// `Process.terminate()` sends `SIGTERM`, which is a *request*: a program may catch
    /// it, and a wedged one cannot answer at all. The event-driven reader means no
    /// dispatch thread is parked meanwhile, but leaving that process alive would still
    /// spend the user's search quota and retain Foundation's process resources after the
    /// caller was told the command had stopped.
    ///
    /// So the grace period ends in `SIGKILL`, which cannot be caught. Foundation then
    /// reaps the direct child and the leak is ended rather than moved somewhere quieter.
    static let terminationGrace: TimeInterval = 2

    /// How long to drain bytes already reaching the pipe after the direct child exits.
    ///
    /// A descendant may have inherited stdout. Waiting for EOF would then make that
    /// unrelated process own this call's lifetime; closing immediately would truncate
    /// an ordinary command whose last buffered chunk is delivered just after its exit
    /// notification. This short grace separates those cases without making the
    /// descendant part of the command Vervellum launched.
    static let postExitDrainGrace: TimeInterval = 0.25

    #if canImport(Glibc)
    /// How often to ask the kernel whether the direct child has exited, on Linux.
    ///
    /// corelibs-foundation learns that a child ended when a socket the child inherited
    /// reaches end-of-file, and every descendant inherits that socket too. Its
    /// termination handler therefore waits for the *last* descendant, which is exactly
    /// the lifetime coupling the drain grace above exists to refuse. A non-reaping
    /// `waitid` sees the direct child's own exit; Foundation still reaps it later. A
    /// search command lives for seconds, so polling at this rate costs a few dozen
    /// wake-ups and adds at most this much latency to a result.
    static let directChildPollInterval: TimeInterval = 0.05
    #endif

    // MARK: Resolving

    /// Where a bare command name is looked for, after `PATH`.
    ///
    /// This list is not redundant with `PATH`, and leaving it out would make the feature
    /// look broken to most of the people using it. A macOS menu-bar agent is launched by
    /// `launchd`, not by a shell, so it inherits `/usr/bin:/bin:/usr/sbin:/sbin` — a
    /// `PATH` that contains none of the places a CLI installs itself. The user's own
    /// shell finds `kagi` instantly and the app does not, which reads as a bug in the
    /// app rather than as the environment difference it is.
    ///
    /// Absolute paths only, and a fixed list: a relative directory in `PATH` means the
    /// program found depends on the working directory, which is not something a
    /// background app should be resolving executables against.
    static var searchDirectories: [String] {
        let home = NSHomeDirectory()
        let path = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
            .filter { $0.hasPrefix("/") }
        return path + [
            "/opt/homebrew/bin",                 // Homebrew, Apple silicon
            "/usr/local/bin",                    // Homebrew, Intel; and the usual manual install
            "/home/linuxbrew/.linuxbrew/bin",
            home + "/.local/bin",                // the install script's default
            home + "/.cargo/bin",                // cargo install
            home + "/.bun/bin",
            "/usr/bin",
            "/bin",
        ]
    }

    func resolve(command: String) -> URL? {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // A path the user wrote is taken as a path, tilde and all, and is not searched
        // for anywhere else. Someone who types `/opt/kagi/bin/kagi` means that file.
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") {
            let expanded = trimmed.hasPrefix("~/")
                ? NSHomeDirectory() + String(trimmed.dropFirst(1))
                : trimmed
            return Self.executableFile(at: expanded)
        }
        // Anything else with a slash in it is relative to this process's working
        // directory — the very dependence the fixed list above refuses to have, and a
        // background app's working directory is whatever it was launched with. Two
        // grammars are documented, a bare name and an absolute path; `./kagi` is neither,
        // and saying so at the settings screen beats resolving it against `/`.
        if trimmed.contains("/") { return nil }

        for directory in Self.searchDirectories {
            if let url = Self.executableFile(at: directory + "/" + trimmed) { return url }
        }
        return nil
    }

    /// The file at `path` if it is a program, or nil.
    ///
    /// The directory check is not pedantry: `isExecutableFile` is true of most
    /// directories, because that is what their execute bit means. Without it a command of
    /// `/tmp` passes configuration and fails much later as "could not start the search
    /// command", which sends whoever reads that looking in the wrong place.
    static func executableFile(at path: String) -> URL? {
        var isDirectory: ObjCBool = false
        let manager = FileManager.default
        guard manager.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue,
              manager.isExecutableFile(atPath: path) else { return nil }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    // MARK: Running

    func run(executable: URL,
             arguments: [String],
             environment: [String: String],
             limit: Int,
             timeout: TimeInterval) async throws -> (status: Int32, output: Data) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        // Pinned rather than inherited, so where the child writes anything of its own
        // does not depend on the directory Vervellum happened to be launched from.
        process.currentDirectoryURL = URL(fileURLWithPath: NSHomeDirectory())
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice

        let control = Control(process: process, pipe: pipe, limit: limit,
                              timeout: timeout) { reason in
            switch reason {
            case .timedOut:
                return ResearchError(
                    "The search command did not finish within \(Int(timeout)) seconds.")
            case .tooMuchOutput:
                return ResearchError(
                    "The search command printed more than \(limit / 1024) KB.")
            case .cancelled:
                return ResearchError.cancelled
            case .readFailed:
                return ResearchError(
                    "Vervellum could not read the search command's output.")
            }
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                control.begin(continuation)
            }
        } onCancel: {
            control.stop(because: .cancelled)
        }
    }

    /// One command's event loop. Nothing blocks this queue: stdout is read only after a
    /// dispatch source reports bytes, and direct-child exit is its own event rather than
    /// something inferred from pipe EOF. That distinction is what prevents a descendant
    /// which inherited stdout from holding the caller forever.
    private final class Control: @unchecked Sendable {

        enum Reason: Equatable { case timedOut, tooMuchOutput, cancelled, readFailed }

        /// How a stop reason is worded. Held here so `stop` can answer the caller from a
        /// timer without knowing what the timeout or the limit was.
        let failure: (Reason) -> Error

        private let process: Process
        private let pipe: Pipe
        private let limit: Int
        private let timeout: TimeInterval
        private let eventQueue: DispatchQueue
        private var source: DispatchSourceRead?
        private var timeoutItem: DispatchWorkItem?
        private var postExitItem: DispatchWorkItem?
        private var escalationItem: DispatchWorkItem?
        #if canImport(Glibc)
        private var directChildPollItem: DispatchWorkItem?
        #endif
        private var launched = false
        private var childExited = false
        private var exitStatus: Int32?
        private var sawEOF = false
        private var output = Data()
        private var stopped: Reason?
        /// True only when the timeout found the direct child already stopped, before any
        /// signal was sent: that exit, clean or not, was the command's own. A child that
        /// exits zero *because* it handled our SIGTERM still timed out.
        private var timeoutFoundNaturalExit = false
        private var completed = false
        private var continuation: CheckedContinuation<(status: Int32, output: Data), Error>?

        init(process: Process, pipe: Pipe, limit: Int, timeout: TimeInterval,
             failure: @escaping (Reason) -> Error) {
            self.process = process
            self.pipe = pipe
            self.limit = limit
            self.timeout = timeout
            self.failure = failure
            self.eventQueue = DispatchQueue(
                label: "ch.lkmc.Vervellum.command.run.\(UUID().uuidString)",
                target: CommandRunner.queue)
        }

        func begin(_ continuation: CheckedContinuation<(status: Int32, output: Data), Error>) {
            eventQueue.async { [self] in
                self.continuation = continuation
                guard let stopped else {
                    launch()
                    return
                }
                complete(throwing: failure(stopped))
            }
        }

        private func launch() {
            // Foundation owns the launched process until it has reaped it. A weak
            // capture avoids a Process-Control retain cycle and, on Darwin, avoids
            // clearing a termination handler while Foundation is still finishing its
            // own pipe bookkeeping.
            process.terminationHandler = { [weak self] ended in
                guard let self else { return }
                let status = ended.terminationStatus
                eventQueue.async { [self] in
                    self.childDidExit(status: status)
                }
            }
            do {
                #if canImport(Glibc)
                try launchWithUnblockedSignals()
                #else
                try process.run()
                #endif
            } catch {
                process.terminationHandler = nil
                // The name and the foreign error are absent: both came from the
                // provider settings or the operating system, and neither is safe or
                // useful in a message the app displays.
                complete(throwing: ResearchError(
                    "Vervellum could not start the search command. Check the "
                    + "command in the provider settings."))
                return
            }
            launched = true

            // `Process` duplicated this descriptor into the child. Keeping the parent's
            // writer open would suppress EOF even for a command with no descendants.
            try? pipe.fileHandleForWriting.close()
            startReading()
            #if canImport(Glibc)
            scheduleDirectChildPoll()
            #endif

            let timeoutItem = DispatchWorkItem { [weak self] in
                self?.stopOnEventQueue(because: .timedOut)
            }
            self.timeoutItem = timeoutItem
            eventQueue.asyncAfter(deadline: .now() + max(0, timeout), execute: timeoutItem)
        }

        #if canImport(Glibc)
        /// Starts the child with no signals blocked.
        ///
        /// corelibs-foundation spawns without `POSIX_SPAWN_SETSIGMASK`, so the child
        /// inherits the launching thread's signal mask, and this runs on a libdispatch
        /// worker, which blocks nearly every signal. A child started from here would keep
        /// `SIGTERM` pending forever: `terminate()` would never be honoured, and every
        /// stop would wait out `terminationGrace` for `SIGKILL`. This thread's own mask
        /// is restored as soon as the spawn returns. Foundation's process-manager thread,
        /// which the first launch creates, keeps the empty mask it inherits here — the
        /// mask it would have had if the first launch had come from any ordinary thread.
        /// Either thread can therefore receive a process-directed signal. Vervellum
        /// installs no signal handlers, so that changes nothing today; a handler added
        /// later must not assume which thread it runs on.
        private func launchWithUnblockedSignals() throws {
            var unblocked = sigset_t()
            var previous = sigset_t()
            sigemptyset(&unblocked)
            pthread_sigmask(SIG_SETMASK, &unblocked, &previous)
            defer { pthread_sigmask(SIG_SETMASK, &previous, nil) }
            try process.run()
        }

        private func scheduleDirectChildPoll() {
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                directChildPollItem = nil
                pollDirectChild(rescheduling: true)
            }
            directChildPollItem = item
            eventQueue.asyncAfter(
                deadline: .now() + CommandRunner.directChildPollInterval, execute: item)
        }

        /// Reports the direct child's exit as soon as the kernel has it, without reaping
        /// it. See `directChildPollInterval` for why Foundation's own report can arrive
        /// only when the last descendant exits. `WNOWAIT` leaves the child waitable, so
        /// Foundation still reaps it, and its pid cannot be reused before then.
        private func pollDirectChild(rescheduling: Bool) {
            // Once Foundation calls the child stopped it has reaped it, and its own
            // report is on the way; asking about a reaped pid could match a recycled one.
            guard launched, !childExited, !completed, process.isRunning else { return }
            var info = siginfo_t()
            if waitid(P_PID, id_t(process.processIdentifier), &info,
                      WEXITED | WNOHANG | WNOWAIT) == 0,
               info._sifields._sigchld.si_pid == process.processIdentifier {
                // The exit code, or the signal number, as Foundation reports it.
                childDidExit(status: info._sifields._sigchld.si_status)
                return
            }
            // Still running, or reaped by Foundation since the guard above, whose handler
            // is then on its way. Keep asking only while Foundation calls it running.
            if rescheduling, process.isRunning { scheduleDirectChildPoll() }
        }
        #endif

        private func startReading() {
            let handle = pipe.fileHandleForReading
            let source = DispatchSource.makeReadSource(
                fileDescriptor: handle.fileDescriptor, queue: eventQueue)
            // The source is read back through `self` rather than captured weakly:
            // corelibs-libdispatch imports it as the non-class-bound
            // `any DispatchSourceRead`, which `weak` cannot apply to on Linux. Handlers
            // run on `eventQueue`, where `cancelReading` clears the property before
            // cancelling, so a cleared property means there is nothing left to read.
            source.setEventHandler { [weak self] in
                guard let self, let source = self.source else { return }
                self.readAnnounced(source.data)
            }
            source.setCancelHandler { try? handle.close() }
            self.source = source
            source.resume()
        }

        /// Reads no more than the dispatch source announced, so this event handler can
        /// never park waiting for a writer. More bytes produce another source event.
        ///
        /// Zero is the exception: it means the write side has hung up, every copy of the
        /// writer included, so reading on to end-of-file cannot park. It must not be
        /// taken as end-of-file itself. Darwin reports zero only once the buffer is
        /// empty, but Linux's libdispatch reports an epoll hang-up as zero even with
        /// bytes still buffered — a short command's last chunk and its exit arrive as one
        /// event, and stopping at the zero would drop that tail.
        private func readAnnounced(_ announced: UInt) {
            guard !completed, !sawEOF else { return }

            var remaining = announced == 0 || announced > UInt(Int.max)
                ? Int.max
                : Int(announced)
            while remaining > 0, !completed, !sawEOF {
                // Keep one byte beyond the limit so crossing it is observable, without
                // overflowing when a caller deliberately uses `Int.max` as no limit.
                let remainingBeforeLimit = limit >= output.count
                    ? limit - output.count
                    : 0
                let room = remainingBeforeLimit == Int.max
                    ? Int.max
                    : remainingBeforeLimit + 1
                let count = min(CommandRunner.chunkSize, remaining, room)
                do {
                    let chunk = try pipe.fileHandleForReading.read(upToCount: count) ?? Data()
                    guard !chunk.isEmpty else {
                        reachedEOF()
                        return
                    }
                    output.append(chunk)
                    remaining -= chunk.count
                    if output.count > limit {
                        stopOnEventQueue(because: .tooMuchOutput)
                        // Nothing more is wanted, even when an earlier stop already
                        // owns the outcome and this one was not recorded.
                        cancelReading()
                        return
                    }
                } catch {
                    stopOnEventQueue(because: .readFailed)
                    return
                }
            }
        }

        private func reachedEOF() {
            guard !sawEOF else { return }
            sawEOF = true
            cancelReading()
            finishIfSettled()
        }

        private func childDidExit(status: Int32) {
            // On Linux both `pollDirectChild` and Foundation report the exit; the first
            // report is the one that counts.
            guard !childExited else { return }
            childExited = true
            #if canImport(Glibc)
            directChildPollItem?.cancel()
            directChildPollItem = nil
            #endif
            exitStatus = status
            timeoutItem?.cancel()
            timeoutItem = nil
            escalationItem?.cancel()
            escalationItem = nil
            guard !completed else { return }

            if let stopped = decidingStop {
                complete(throwing: failure(stopped))
                return
            }
            if sawEOF {
                finishIfSettled()
                return
            }

            // The direct child is done, but a final pipe event may still be queued.
            // Give it one short drain window; EOF is not required because a descendant
            // may own another copy of the writer.
            let postExitItem = DispatchWorkItem { [weak self] in
                self?.finishAfterDrainGrace()
            }
            self.postExitItem = postExitItem
            eventQueue.asyncAfter(
                deadline: .now() + CommandRunner.postExitDrainGrace,
                execute: postExitItem)
        }

        private func finishAfterDrainGrace() {
            guard !completed, childExited else { return }
            // Read-source data is meaningful only in its event handler. Reading its
            // last observed count here could issue a stale read and block until an
            // inherited writer closes — the exact lifetime coupling this grace avoids.
            // Any bytes present during the grace schedule their own event on this same
            // serial queue and are therefore drained before this timer runs.
            cancelReading()
            finishIfSettled(pipeMayRemainOpen: true)
        }

        private func finishIfSettled(pipeMayRemainOpen: Bool = false) {
            guard childExited, sawEOF || pipeMayRemainOpen,
                  let status = exitStatus else { return }
            if let stopped = decidingStop {
                complete(throwing: failure(stopped))
            } else if output.count > limit {
                // Only a natural exit at the deadline gets here: the reader stays open
                // through its drain, and a crossing there cannot record its own stop
                // because the timeout's is already recorded. The limit still holds.
                complete(throwing: failure(.tooMuchOutput))
            } else {
                complete(returning: (status, output))
            }
        }

        /// The recorded stop, unless it is a timeout that found the direct child already
        /// gone — then the command's own exit decides the outcome.
        private var decidingStop: Reason? {
            stopped == .timedOut && timeoutFoundNaturalExit ? nil : stopped
        }

        /// Records why the command is being stopped and stops it. The first reason wins:
        /// a timeout that fires while a cancellation is already tearing the process down
        /// should not relabel what happened.
        func stop(because reason: Reason) {
            eventQueue.async { [weak self] in self?.stopOnEventQueue(because: reason) }
        }

        private func stopOnEventQueue(because reason: Reason) {
            guard !completed, stopped == nil else { return }
            #if canImport(Glibc)
            // Foundation's `isRunning`, used below to recognise a natural exit at the
            // deadline, stays true on Linux until the last descendant exits. Ask the
            // kernel first, so the exit is recorded before the timeout is.
            if reason == .timedOut {
                pollDirectChild(rescheduling: false)
                guard !completed else { return }
            }
            #endif
            stopped = reason
            timeoutItem?.cancel()
            timeoutItem = nil

            // A deadline and a natural exit can become runnable together. Preserve the
            // direct child's final pipe events while its termination callback catches
            // up. This flag is set only before Vervellum sends SIGTERM: a command that
            // handles our signal by exiting zero still exceeded its deadline, while one
            // that had already died of a signal of its own did not run too long.
            if reason == .timedOut, launched {
                if childExited {
                    timeoutFoundNaturalExit = true
                    return
                }
                if !childExited, !process.isRunning {
                    timeoutFoundNaturalExit = true
                    return
                }
            }

            postExitItem?.cancel()
            postExitItem = nil
            cancelReading()

            guard launched else {
                // `begin` has not run yet. It will see this reason after attaching the
                // continuation and answer without launching a process.
                if continuation != nil { complete(throwing: failure(reason)) }
                return
            }
            guard !childExited else {
                complete(throwing: failure(reason))
                return
            }

            if process.isRunning { process.terminate() }
            let escalationItem = DispatchWorkItem { [weak self] in
                guard let self else { return }
                guard !childExited else { return }
                // `isRunning` first, so a child already reaped is not signalled — which
                // also keeps this off a pid the system has since handed to somebody else.
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                complete(throwing: failure(reason))
            }
            self.escalationItem = escalationItem
            eventQueue.asyncAfter(
                deadline: .now() + CommandRunner.terminationGrace,
                execute: escalationItem)
        }

        private func cancelReading() {
            guard let source else {
                if !launched { try? pipe.fileHandleForReading.close() }
                return
            }
            self.source = nil
            source.cancel()
        }

        /// Resumes the caller once and cancels every event that no longer owns work.
        private func complete(returning value: (status: Int32, output: Data)) {
            guard !completed else { return }
            takeContinuation()?.resume(returning: value)
        }

        private func complete(throwing error: Error) {
            guard !completed else { return }
            takeContinuation()?.resume(throwing: error)
        }

        private func takeContinuation()
            -> CheckedContinuation<(status: Int32, output: Data), Error>? {
            completed = true
            timeoutItem?.cancel()
            timeoutItem = nil
            postExitItem?.cancel()
            postExitItem = nil
            escalationItem?.cancel()
            escalationItem = nil
            #if canImport(Glibc)
            directChildPollItem?.cancel()
            directChildPollItem = nil
            #endif
            cancelReading()
            try? pipe.fileHandleForWriting.close()
            let continuation = self.continuation
            self.continuation = nil
            return continuation
        }
    }
}
