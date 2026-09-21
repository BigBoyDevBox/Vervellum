import Foundation

/// One thread's live state: the thread itself, and the run in flight on it if any.
///
/// A session survives being hidden. Starting a new thread or opening an old one
/// *detaches* the session rather than cancelling it — that is what lets several
/// researches run in parallel. Each detached session keeps mutating and persisting
/// its own thread, and its run stops only on an explicit `cancel()`/`discard()` or
/// when the process ends.
///
/// Like `ResearchRunner`, this type has no UI or actor isolation on purpose.
/// Runner callbacks arrive on whatever thread the runner happened to be on, so
/// every mutation they cause is handed back through `hop`, which the front end
/// supplies: `DispatchQueue.main.async` on macOS, `GTK.onMainLoop` on Linux —
/// a GLib main loop never drains libdispatch's queue. Calls *into* the session
/// (`ask`, `cancel`, …) come from the UI thread and report synchronously, which is
/// the same contract the engines already worked under.
final class ResearchSession {

    /// What changed in `thread`, handed to `onMutate`.
    struct Mutation {
        /// The turn that changed, or nil when the thread itself did.
        var turnID: UUID?
        /// True when the change is more than appended answer text — a stage move,
        /// sources or verdicts landing, a notice. A renderer that coalesces repaints
        /// (the Linux panel redraws at most ten times a second) must still draw a
        /// structural mutation immediately: those are the moments the user is
        /// waiting for.
        var isStructural: Bool
    }

    private(set) var thread: ResearchThread
    private(set) var isRunning = false
    /// True after `discard()`. A discarded session is dead: its run is cancelled and
    /// nothing it does is persisted, because persisting would resurrect a thread the
    /// user just deleted.
    private(set) var isDiscarded = false

    var id: UUID { thread.id }

    private var task: Task<Void, Never>?
    private var runningTurnID: UUID?

    private let preferences: CorePreferences
    private let secrets: SecretStore
    private let logSink: LogSink
    private let hop: (@escaping () -> Void) -> Void

    /// Every mutation of `thread`, including one per streamed chunk: repaint.
    var onMutate: ((ResearchSession, Mutation) -> Void)?
    /// Structural moments only — ask, cancel, finish — when the thread is worth
    /// persisting. Writing on every streamed token would upsert the whole library
    /// once per token for nothing: the debounced file write makes mid-stream
    /// persistence nearly free to lose.
    var onPersist: ((ResearchSession) -> Void)?
    /// `isRunning` flipped, so a front end can redraw its Stop affordance.
    var onRunningChange: ((ResearchSession) -> Void)?

    init(thread: ResearchThread,
         preferences: CorePreferences,
         secrets: SecretStore,
         logSink: LogSink,
         hop: @escaping (@escaping () -> Void) -> Void) {
        self.thread = thread
        self.preferences = preferences
        self.secrets = secrets
        self.logSink = logSink
        self.hop = hop
    }

    // MARK: Asking

    /// Appends a turn for `question` and starts researching it.
    func ask(_ question: String, mode: ResearchRunner.Mode = .research) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning, !isDiscarded else { return }

        var turn = ResearchTurn(question: trimmed)
        turn.model = preferences.providerSettings.modelName
        if mode == .direct { turn.notices = [.noEvidence] }
        thread.turns.append(turn)
        thread.updatedAt = Date()
        runningTurnID = turn.id
        isRunning = true
        onMutate?(self, Mutation(turnID: turn.id, isStructural: true))
        onRunningChange?(self)
        persist()

        let id = turn.id
        // An immutable copy for the concurrent closure: capturing the mutable `turn`
        // would be a reference to a captured `var` in concurrently-executing code.
        let submitted = turn
        // Informational turns (`/help`, "not supported here") carry an empty question
        // and are filtered out again by `ResearchContext`; dropping them here just
        // keeps the history honest at the source.
        let history = thread.turns.filter { $0.id != id && !$0.question.isEmpty }
        let runner = ResearchRunner(
            environment: .init(preferences: preferences, secrets: secrets),
            trace: ResearchTrace(sink: logSink))

        task = Task { [weak self] in
            guard let self else { return }
            let finished = await runner.run(submitted, mode: mode, history: history) { snapshot in
                // The runner reports from whatever thread it is running on; `hop`
                // puts the mutation back on the front end's UI thread, in order.
                self.hop { [weak self] in self?.apply(snapshot) }
            }
            self.hop { [weak self] in self?.finish(finished) }
        }
    }

    /// Re-runs one turn's question.
    ///
    /// Takes the turn's id rather than assuming the last one: a thread can hold
    /// several failed turns, and "retry" on the third of five must not silently
    /// delete the fifth. Only a turn that is still last is replaced in place;
    /// retrying an older one asks the question again at the end, where the answer
    /// belongs.
    func retry(_ id: UUID) {
        guard !isRunning, let turn = thread.turns.first(where: { $0.id == id }) else { return }
        let question = turn.question
        // Re-ask the way the user asked. A turn the *planner* decided needed no
        // search also carries the no-evidence notice, but should be researched in
        // full.
        let mode: ResearchRunner.Mode = turn.wasAskedDirectly ? .direct : .research
        if thread.turns.last?.id == id { thread.turns.removeLast() }
        ask(question, mode: mode)
    }

    /// Stops the running turn. The partial answer is kept: a half-written answer
    /// with its sources is often still useful, and discarding it would punish the
    /// user for changing their mind.
    func cancel() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        let cancelledID = runningTurnID
        if let id = cancelledID,
           let index = thread.turns.firstIndex(where: { $0.id == id }),
           !thread.turns[index].stage.isTerminal {
            thread.turns[index].stage = .cancelled
            thread.turns[index].duration = Date().timeIntervalSince(thread.turns[index].askedAt)
            thread.updatedAt = Date()
        }
        runningTurnID = nil
        isRunning = false
        onRunningChange?(self)
        onMutate?(self, Mutation(turnID: cancelledID, isStructural: true))
        persist()
    }

    /// Cancels the run and seals the session: nothing it does is persisted again.
    ///
    /// Deleting a thread goes through here — otherwise the still-running turn's
    /// next checkpoint would re-save the thread the user just deleted.
    func discard() {
        isDiscarded = true
        task?.cancel()
        task = nil
        runningTurnID = nil
        if isRunning {
            isRunning = false
            onRunningChange?(self)
        }
    }

    /// Adds a turn the front end produced itself — `/help`, or "that command is not
    /// supported here". It renders like any other turn; `persistableThread` keeps
    /// it out of the archive and `ask` keeps it out of the model's history.
    func appendLocalTurn(_ turn: ResearchTurn) {
        thread.turns.append(turn)
        thread.updatedAt = Date()
        onMutate?(self, Mutation(turnID: turn.id, isStructural: true))
    }

    /// The thread as it is stored: research only, with the front end's own notice
    /// turns removed. Both this filter and `ResearchContext` key off the empty
    /// question.
    var persistableThread: ResearchThread {
        var stored = thread
        stored.turns.removeAll { $0.question.isEmpty }
        return stored
    }

    // MARK: Turn mutation

    /// Applies a runner snapshot to the turn it belongs to and reports it.
    private func apply(_ snapshot: ResearchTurn) {
        guard let index = thread.turns.firstIndex(where: { $0.id == snapshot.id }) else { return }
        let previous = thread.turns[index]
        thread.turns[index] = snapshot
        thread.updatedAt = Date()
        let structural = previous.stage != snapshot.stage
            || previous.sources.count != snapshot.sources.count
            || previous.findings.count != snapshot.findings.count
            || previous.notices != snapshot.notices
        onMutate?(self, Mutation(turnID: snapshot.id, isStructural: structural))
    }

    private func finish(_ finished: ResearchTurn) {
        apply(finished)
        // A late finish from an earlier run — cancelled, then replaced by a fresh
        // ask on the same thread — still reports back. Its final snapshot is worth
        // keeping and worth persisting, but it must not clear the newer run's
        // state.
        guard runningTurnID == finished.id else { persist(); return }
        runningTurnID = nil
        task = nil
        isRunning = false
        onRunningChange?(self)
        persist()
    }

    private func persist() {
        guard !isDiscarded else { return }
        onPersist?(self)
    }
}
