import Foundation
import SwiftUI

/// The macOS front end's view model over the shared research pipeline.
///
/// Everything that decides *what* a research turn does — the four stages, the prompts,
/// the validation — lives in `ResearchRunner`, and everything about a run's lifetime
/// lives in `ResearchSession`; both are compiled into the Linux build too. This class
/// is the thin part: it keeps a session per thread, decides which one is visible,
/// publishes changes to SwiftUI, and marshals the runner's progress onto the main
/// queue.
///
/// Keeping the split here rather than one layer down is deliberate. `ObservableObject`
/// comes from Combine, which does not exist on Linux, so an engine that published
/// directly could not be shared at all. A view model per platform over one pipeline is
/// a few dozen lines of forwarding and keeps every rule in one place.
final class ResearchEngine: ObservableObject {

    typealias Mode = ResearchRunner.Mode

    /// The visible session's thread. A detached session keeps mutating its own
    /// thread — and keeps persisting it — but only the visible one republishes here.
    @Published private(set) var thread: ResearchThread
    /// Whether the *visible* thread has a run in flight. See `isBusy` for "any".
    @Published private(set) var isRunning = false
    /// Every thread with a run in flight, so the history list can mark the ones
    /// still working.
    @Published private(set) var runningThreadIDs: Set<UUID> = []

    private let preferences: CorePreferences
    private let secrets: SecretStore
    private let logSink: LogSink
    /// Live state per thread. A session stays in the map while it might be returned
    /// to — above all while its run is still going.
    private var sessions: [UUID: ResearchSession] = [:]
    private var activeSession: ResearchSession

    /// Called whenever a session's thread reaches a point worth persisting. Any
    /// session can fire it, not just the visible one — a backgrounded run's answer
    /// belongs on disk too.
    var onThreadChanged: ((ResearchThread) -> Void)?

    init(thread: ResearchThread = ResearchThread(),
         preferences: CorePreferences,
         secrets: SecretStore,
         logSink: LogSink = OSLogSink()) {
        self.thread = thread
        self.preferences = preferences
        self.secrets = secrets
        self.logSink = logSink
        let session = ResearchSession(thread: thread,
                                      preferences: preferences,
                                      secrets: secrets,
                                      logSink: logSink,
                                      hop: Self.hop)
        sessions[session.id] = session
        activeSession = session
        wire(session)
    }

    /// Runner callbacks land on `DispatchQueue.main` — FIFO, so streamed chunks
    /// arrive in the order they were produced.
    private static let hop: (@escaping () -> Void) -> Void = { work in
        DispatchQueue.main.async(execute: work)
    }

    // MARK: Thread control

    /// Starts a fresh thread. The previous session is *detached*, not cancelled: a
    /// run in flight on it keeps going and persists when it finishes, which is what
    /// lets several researches run in parallel.
    func startNewThread() {
        activate(makeSession(thread: ResearchThread()))
    }

    /// Makes `thread` visible. If the thread still has a live session — a run
    /// detached by `/new`, say — the session is reactivated and its *live* thread
    /// shown rather than the possibly staler persisted copy the caller passes in.
    func replaceThread(with thread: ResearchThread) {
        activate(sessions[thread.id] ?? makeSession(thread: thread))
    }

    /// Stops the visible session's run. A detached run is unaffected; to stop it,
    /// open its thread from history first.
    func cancel() {
        activeSession.cancel()
    }

    /// Whether any session has a run in flight. This is what "don't dismiss the
    /// panel mid-research" means now that a hidden run still runs.
    var isBusy: Bool { !runningThreadIDs.isEmpty }

    /// Drops a thread's session without persisting again. Deleting from history must
    /// also cancel the run — otherwise its next checkpoint would re-save the thread
    /// the user just deleted.
    func discardSession(for id: UUID) {
        guard let session = sessions[id] else { return }
        session.discard()
        sessions.removeValue(forKey: id)
        // Deleting the thread on display leaves nothing to show; start fresh.
        if activeSession === session {
            activate(makeSession(thread: ResearchThread()))
        }
    }

    /// Drops every session. Wired to "delete all history": every live run stops and
    /// the visible thread is replaced by a fresh one.
    func discardAllSessions() {
        for session in sessions.values { session.discard() }
        sessions.removeAll()
        activate(makeSession(thread: ResearchThread()))
    }

    // MARK: Asking

    /// Appends a turn for `question` and starts researching it on the visible thread.
    func ask(_ question: String, mode: Mode = .research) {
        activeSession.ask(question, mode: mode)
    }

    /// Re-runs one turn's question on the visible thread. See `ResearchSession.retry`.
    func retry(_ id: UUID) {
        activeSession.retry(id)
    }

    // MARK: Sessions

    private func makeSession(thread: ResearchThread) -> ResearchSession {
        let session = ResearchSession(thread: thread,
                                      preferences: preferences,
                                      secrets: secrets,
                                      logSink: logSink,
                                      hop: Self.hop)
        wire(session)
        return session
    }

    private func activate(_ session: ResearchSession) {
        sessions[session.id] = session
        activeSession = session
        thread = session.thread
        if isRunning != session.isRunning { isRunning = session.isRunning }
    }

    private func wire(_ session: ResearchSession) {
        session.onMutate = { [weak self] session, _ in
            guard let self, session === self.activeSession else { return }
            self.thread = session.thread
        }
        session.onPersist = { [weak self] session in
            self?.onThreadChanged?(session.persistableThread)
        }
        session.onRunningChange = { [weak self] _ in self?.syncRunning() }
    }

    private func syncRunning() {
        let running = Set(sessions.values.filter(\.isRunning).map(\.id))
        if runningThreadIDs != running { runningThreadIDs = running }
        let activeRunning = activeSession.isRunning
        if isRunning != activeRunning { isRunning = activeRunning }
    }
}
