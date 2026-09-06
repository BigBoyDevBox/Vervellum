import Foundation

/// Everything Vervellum keeps on disk between launches: past research threads.
///
/// Versioned from the first release. `version` is checked on load and a document
/// claiming a *newer* version is treated as read-only, because re-encoding it would
/// write fields this build lossily decoded back under the newer stamp — destroying
/// data a future build would have understood.
struct ThreadLibrary: Codable, Equatable {

    static let currentVersion = 1
    /// How many threads are kept. Old research is the least valuable thing on the
    /// disk and the file is read wholesale at launch, so the list is bounded.
    static let maxThreads = 200

    var version: Int = ThreadLibrary.currentVersion
    /// Newest first.
    var threads: [ResearchThread] = []

    /// Inserts or replaces `thread`, keeping the list newest-first and bounded.
    /// An empty thread is never stored: summoning the panel and dismissing it
    /// without asking anything should leave no trace.
    mutating func upsert(_ thread: ResearchThread) {
        threads.removeAll { $0.id == thread.id }
        guard !thread.isEmpty else { return }
        threads.insert(thread, at: 0)
        if threads.count > Self.maxThreads {
            threads.removeLast(threads.count - Self.maxThreads)
        }
    }

    mutating func remove(id: UUID) {
        threads.removeAll { $0.id == id }
    }

    /// Threads whose title or any question matches `query`, newest first.
    func search(_ query: String) -> [ResearchThread] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !needle.isEmpty else { return threads }
        return threads.filter { thread in
            thread.turns.contains { turn in
                turn.question.lowercased().contains(needle)
                    || turn.answer.lowercased().contains(needle)
            }
        }
    }
}
