import Foundation

/// Small pure formatters shared by the panel's views.
///
/// Deliberately not members of the views that use them: SwiftUI's `View` protocol is
/// main-actor isolated, and SE-0316 infers that isolation for the whole conforming
/// type — including its `static` members. A pure function tucked inside a view is then
/// needlessly awkward to call from a unit test.
enum Formatting {

    /// A wall-clock duration: `4.2s` under a minute, `1:35` above it.
    ///
    /// Seconds with one decimal read as precision at the scale a research run takes;
    /// minutes and seconds read as duration. Switching at 60 keeps both honest.
    static func duration(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "—" }
        guard seconds >= 60 else { return String(format: "%.1fs", seconds) }
        // `Int(_: Double)` traps above `Int.max`, and a clock jump or a corrupted
        // stored duration can produce one. A run that claims to have taken a decade is
        // wrong either way; saying so beats crashing.
        guard let whole = Int(exactly: seconds.rounded(.down)), whole < 360_000 else { return "—" }
        return String(format: "%d:%02d", whole / 60, whole % 60)
    }

    /// A short relative age for a list row: `just now`, `4m ago`, `3h ago`, `2d ago`,
    /// `5w ago`, or a bare date when even weeks get wide.
    ///
    /// `RelativeDateTimeFormatter` does not exist in corelibs Foundation, so the Linux
    /// history list cannot use it — and this scale (a pick-a-thread row, not prose) is
    /// better served by tokens that stay narrow at every text scale anyway.
    static func relativeDate(_ date: Date, from now: Date = Date()) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds.isFinite, seconds >= 0 else { return "just now" }
        if seconds < 60 { return "just now" }
        let minutes = Int(seconds / 60)
        if minutes < 60 { return "\(minutes)m ago" }
        let hours = minutes / 60
        if hours < 24 { return "\(hours)h ago" }
        let days = hours / 24
        if days < 14 { return "\(days)d ago" }
        let weeks = days / 7
        if weeks < 8 { return "\(weeks)w ago" }
        // Past two months the count stops being a feeling and starts being a calendar.
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
