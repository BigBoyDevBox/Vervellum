import Foundation
import SwiftUI

/// The macOS front end's view model over the shared research pipeline.
///
/// Everything that decides *what* a research turn does — the four stages, the prompts,
/// the validation — lives in `ResearchRunner`, which knows nothing about AppKit,
/// SwiftUI or Combine and is compiled into the Linux build too. This class is the thin
/// part: it owns the thread, publishes changes to SwiftUI, and marshals the runner's
/// progress onto the main queue.
///
/// Keeping the split here rather than one layer down is deliberate. `ObservableObject`
/// comes from Combine, which does not exist on Linux, so an engine that published
/// directly could not be shared at all. A view model per platform over one pipeline is
/// a few dozen lines of forwarding and keeps every rule in one place.
final class ResearchEngine: ObservableObject {

    typealias Mode = ResearchRunner.Mode

    @Published private(set) var thread: ResearchThread
    @Published private(set) var isRunning = false
    /// The question waiting for the running turn to finish, if any. Published so the
    /// composer can show what will be asked and offer to cancel it. One slot: a second
    /// submit replaces the first, and the chip always shows the current occupant.
    @Published private(set) var queuedQuestion: String?
    private var queuedMode: Mode = .research

    private let preferences: CorePreferences
    private let secrets: SecretStore
    private let logSink: LogSink
    private var task: Task<Void, Never>?
    private var runningTurnID: UUID?

    /// Called whenever the thread changes, so the store can persist it.
    var onThreadChanged: ((ResearchThread) -> Void)?

    init(thread: ResearchThread = ResearchThread(),
         preferences: CorePreferences,
         secrets: SecretStore,
         logSink: LogSink = OSLogSink()) {
        self.thread = thread
        self.preferences = preferences
        self.secrets = secrets
        self.logSink = logSink
    }

    // MARK: Thread control

    func replaceThread(with thread: ResearchThread) {
        cancelRun()
        queuedQuestion = nil
        self.thread = thread
    }

    func startNewThread() {
        cancelRun()
        queuedQuestion = nil
        thread = ResearchThread()
        publishChange()
    }

    /// Stops the running turn. The partial answer is kept: a half-written answer with
    /// its sources is often still useful, and discarding it would punish the user for
    /// changing their mind.
    ///
    /// A deliberate Stop also spends the queue: stopping the current research is not
    /// a withdrawal of the question already waiting behind it.
    func cancel() {
        cancelRun()
        askNextIfQueued()
    }

    /// Stops the running turn without touching the queue. The path for context
    /// switches — new thread, opening another thread — where the queued question
    /// belongs to the thread being left, not the one being opened.
    private func cancelRun() {
        guard let task else { return }
        task.cancel()
        self.task = nil
        if let id = runningTurnID {
            update(id) { turn in
                if !turn.stage.isTerminal {
                    turn.stage = .cancelled
                    turn.duration = Date().timeIntervalSince(turn.askedAt)
                }
            }
        }
        runningTurnID = nil
        isRunning = false
        publishChange()
    }

    // MARK: Asking

    /// Appends a turn for `question` and starts researching it.
    func ask(_ question: String, mode: Mode = .research) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isRunning else { return }

        var turn = ResearchTurn(question: trimmed)
        turn.model = preferences.providerSettings.modelName
        if mode == .direct { turn.notices = [.noEvidence] }
        thread.turns.append(turn)
        thread.updatedAt = Date()
        runningTurnID = turn.id
        isRunning = true
        publishChange()

        let id = turn.id
        // An immutable copy for the concurrent closure: capturing the mutable `turn`
        // would be a reference to a captured `var` in concurrently-executing code.
        let submitted = turn
        let history = thread.turns.filter { $0.id != id }
        let runner = ResearchRunner(
            environment: .init(preferences: preferences, secrets: secrets),
            trace: ResearchTrace(sink: logSink))

        task = Task { [weak self] in
            // The runner reports from whatever thread it is running on, so every
            // snapshot is hopped onto the main queue in order. `async` is FIFO, so the
            // streamed chunks arrive in the order they were produced.
            let finished = await runner.run(submitted, mode: mode, history: history) { snapshot in
                DispatchQueue.main.async { self?.apply(snapshot) }
            }
            // The same queue as the snapshots, not `MainActor.run`. Both land on the
            // main thread, but mixing the two mechanisms means the completion could be
            // scheduled ahead of snapshots already queued — and the final turn would
            // then be overwritten by an earlier, partial one.
            DispatchQueue.main.async { self?.finish(id, with: finished) }
        }
    }

    /// Queues `question` to be asked the moment the running turn finishes.
    ///
    /// A research run is 10–60 s of dead time in which the user has usually already
    /// thought of the follow-up; locking the composer for that stretch wastes it. One
    /// slot, newest wins — the UI shows the current occupant, so replacement is
    /// visible rather than surprising.
    func enqueue(_ question: String, mode: Mode = .research) {
        let trimmed = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, isRunning else { return }
        queuedQuestion = trimmed
        queuedMode = mode
    }

    /// Drops the queued question without asking it.
    func cancelQueued() {
        queuedQuestion = nil
    }

    /// Asks the queued question if no run is active. Called when a turn finishes —
    /// including one the user stopped, since stopping the current research is not a
    /// withdrawal of the question already queued behind it.
    private func askNextIfQueued() {
        guard !isRunning, let question = queuedQuestion else { return }
        queuedQuestion = nil
        ask(question, mode: queuedMode)
    }

    /// Re-runs one turn's question.
    ///
    /// Takes the turn's id rather than assuming the last one: a thread can hold several
    /// failed turns, and "retry" on the third of five must not silently delete the
    /// fifth. Only a turn that is still last is replaced in place; retrying an older one
    /// asks the question again at the end, where the answer belongs.
    func retry(_ id: UUID) {
        guard !isRunning, let turn = thread.turns.first(where: { $0.id == id }) else { return }
        let question = turn.question
        // Re-ask the way the user asked. A turn the *planner* decided needed no search
        // also carries the no-evidence notice, but should be researched again in full.
        let mode: Mode = turn.wasAskedDirectly ? .direct : .research
        if thread.turns.last?.id == id { thread.turns.removeLast() }
        ask(question, mode: mode)
    }

    // MARK: Turn mutation

    private func apply(_ snapshot: ResearchTurn) {
        guard let index = thread.turns.firstIndex(where: { $0.id == snapshot.id }) else { return }
        thread.turns[index] = snapshot
        thread.updatedAt = Date()
    }

    private func update(_ id: UUID, _ body: (inout ResearchTurn) -> Void) {
        guard let index = thread.turns.firstIndex(where: { $0.id == id }) else { return }
        body(&thread.turns[index])
        thread.updatedAt = Date()
    }

    private func finish(_ id: UUID, with turn: ResearchTurn) {
        apply(turn)
        if runningTurnID == id {
            runningTurnID = nil
            isRunning = false
            task = nil
            // Inside the `if`: only the finish of the *current* run may spend the
            // queue. A late finish from a run the user already cancelled and replaced
            // would otherwise drop the queued question into `ask`'s `isRunning` guard
            // and silently lose it.
            askNextIfQueued()
        }
        publishChange()
    }

    private func publishChange() {
        onThreadChanged?(thread)
    }
}
