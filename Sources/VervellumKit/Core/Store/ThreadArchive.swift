import Foundation
import Dispatch

/// Loads and saves the thread library as JSON, on every platform.
///
/// Writes are **atomic** and **debounced**, keeping one `.bak` of the previous good
/// file: a research turn mutates the document on every streamed chunk, so writing
/// straight through would hammer the disk, and writing non-atomically would leave a
/// truncated file if the app were killed mid-answer.
///
/// The debounce runs on a **private serial queue**, not the main queue. That is not an
/// optimisation — `DispatchQueue.main` is only drained on Linux if something calls
/// `dispatchMain()`, and a GTK application runs a GLib main loop instead, so a
/// main-queue timer would simply never fire there. Using an owned queue also keeps the
/// file write off whichever thread is streaming the answer.
///
/// The whole archive is a no-op when history is disabled, and `eraseEverything()`
/// removes the file rather than writing an empty one — "off" has to mean the bytes are
/// gone, not that they are hidden.
final class ThreadArchive {

    /// Invoked after any change to `library`, so a platform can republish it.
    var onChange: (() -> Void)?

    private(set) var library: ThreadLibrary

    /// True when the file on disk claims a newer document version than this build
    /// understands. In that case the archive never writes.
    let isReadOnly: Bool

    /// When false, nothing is written and nothing is remembered.
    var isHistoryEnabled: Bool {
        didSet {
            guard oldValue != isHistoryEnabled else { return }
            // Turning history *on* stores nothing yet: writing here would create a file
            // holding an empty library before the user has any threads. The next
            // `save(_:)` writes it.
            guard !isHistoryEnabled else { onChange?(); return }
            // Forget in memory as well as on disk. Erasing only the file would leave
            // every thread loaded, so switching history back on would write them all out
            // again — the user's "delete this" would have been a no-op.
            library.threads.removeAll()
            try? eraseEverything()
            onChange?()
        }
    }

    private let fileURL: URL
    private let fileManager: FileManager
    private let debounce: TimeInterval
    private let queue = DispatchQueue(label: "\(AppIdentity.bundleIdentifier).threads")
    /// Touched only from the thread that owns the archive (the UI thread). The work
    /// item it holds runs on `queue` and never reads it back, so there is nothing to
    /// synchronise.
    private var pendingSave: DispatchWorkItem?
    private var hasPendingChanges = false

    init(fileURL: URL,
         fileManager: FileManager = .default,
         historyEnabled: Bool = true,
         debounce: TimeInterval = 1.0) {
        self.fileURL = fileURL
        self.fileManager = fileManager
        self.debounce = debounce
        self.isHistoryEnabled = historyEnabled

        // The file is read for its *version* even when history is off, and only adopted
        // when it is on. Skipping the read entirely would leave `isReadOnly` false, so a
        // user who launches with history disabled and then enables it would write an
        // empty v1 document straight over a newer build's file — exactly the loss this
        // flag exists to prevent.
        let onDisk = Self.load(from: fileURL, fileManager: fileManager)
        isReadOnly = (onDisk?.version ?? ThreadLibrary.currentVersion) > ThreadLibrary.currentVersion
        library = historyEnabled ? (onDisk ?? ThreadLibrary()) : ThreadLibrary()
        if isReadOnly {
            // `onDisk?.version`, not `library.version`: with history disabled the
            // in-memory library is a fresh document and would report the wrong number.
            // Built as one string first: `.utf8` binds tighter than `+`, so applying it
            // to the last literal of a concatenation is a type error, not a byte view.
            let warning = "vervellum warning: threads file is version \(onDisk?.version ?? -1) "
                + "but this build understands \(ThreadLibrary.currentVersion) — history is "
                + "read-only so the newer file isn't downgraded.\n"
            FileHandle.standardError.write(Data(warning.utf8))
        }
    }

    // MARK: Mutation

    func save(_ thread: ResearchThread) {
        guard isHistoryEnabled else { return }
        library.upsert(thread)
        onChange?()
        scheduleSave()
    }

    func delete(id: UUID) {
        library.remove(id: id)
        onChange?()
        scheduleSave()
    }

    func deleteAll() {
        library.threads.removeAll()
        try? eraseEverything()
        onChange?()
    }

    /// The bytes currently on disk, or nil when there is no file. Used to skip a write
    /// that would change nothing.
    private func currentContents() -> Data? { fileManager.contents(atPath: fileURL.path) }

    /// Removes the stored file and its backup outright.
    ///
    /// The deletion runs *on the write queue*. Deleting off-queue would race a debounced
    /// write that is already running, and the file the user just erased would reappear a
    /// fraction of a second later.
    func eraseEverything() throws {
        pendingSave?.cancel()
        pendingSave = nil
        hasPendingChanges = false

        var failure: Error?
        queue.sync {
            for url in [fileURL, backupURL] where fileManager.fileExists(atPath: url.path) {
                do { try fileManager.removeItem(at: url) } catch { failure = error }
            }
        }
        // Reported, not swallowed. "History off means the bytes are gone" is a promise
        // the interface makes; if the file is still there the user has to be told.
        if let failure { throw failure }
    }

    /// Writes any pending change before returning. Called at termination and on
    /// dismissal, where a lost second of work would be a lost answer.
    ///
    /// `queue.sync` rather than a direct call: a debounced write may already be running
    /// on the queue, and two overlapping `.bak` rotations would leave the backup in an
    /// undefined state. Serialising through the same queue makes the ordering explicit.
    func flush() {
        guard hasPendingChanges else { return }
        pendingSave?.cancel()
        pendingSave = nil
        hasPendingChanges = false
        let snapshot = library
        queue.sync { self.writeNow(snapshot) }
    }

    // MARK: Persistence

    private var backupURL: URL { fileURL.appendingPathExtension("bak") }

    private func scheduleSave() {
        guard isHistoryEnabled, !isReadOnly else { return }
        hasPendingChanges = true
        pendingSave?.cancel()
        // Snapshot now, on the caller's thread. The work item must not read `library`
        // later: it runs on another queue while the answer is still being appended to.
        let snapshot = library
        let work = DispatchWorkItem { [weak self] in self?.writeNow(snapshot) }
        pendingSave = work
        queue.asyncAfter(deadline: .now() + debounce, execute: work)
    }

    private func writeNow(_ snapshot: ThreadLibrary) {
        guard isHistoryEnabled, !isReadOnly else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)

            try fileManager.createDirectory(at: fileURL.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
            // Skip a write that would change nothing. `flush()` is called on every
            // dismissal and at termination, and without this each one rotates the
            // previous file into `.bak` — after two flushes the backup is a byte-perfect
            // copy of the live file and has stopped being a recovery copy at all.
            if currentContents() == data { return }

            // Rotate the previous good file, so a failure during the write still leaves
            // one recoverable copy — and only now, when the contents really differ.
            if fileManager.fileExists(atPath: fileURL.path) {
                try? fileManager.removeItem(at: backupURL)
                try? fileManager.copyItem(at: fileURL, to: backupURL)
            }
            try data.write(to: fileURL, options: [.atomic])
            // Research questions are personal. Keep the file owner-only rather than
            // inheriting the umask.
            try? fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
        } catch {
            FileHandle.standardError.write(Data("vervellum warning: could not save threads\n".utf8))
        }
    }

    private static func load(from url: URL, fileManager: FileManager) -> ThreadLibrary? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for candidate in [url, url.appendingPathExtension("bak")] {
            guard let data = fileManager.contents(atPath: candidate.path) else { continue }
            if let library = try? decoder.decode(ThreadLibrary.self, from: data) {
                if candidate != url {
                    FileHandle.standardError.write(Data(
                        "vervellum warning: threads file was unreadable; recovered the .bak copy.\n".utf8))
                }
                return library
            }
        }
        return nil
    }
}
