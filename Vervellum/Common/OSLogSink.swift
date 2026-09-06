import Foundation
import os

/// Routes the shared pipeline's diagnostics into the unified system log.
///
/// macOS-only, because `os.Logger` is. The messages themselves are composed by
/// `ResearchTrace`, which is shared — this only decides where they land, so the rule
/// about what may be logged cannot drift between platforms.
///
/// Everything is marked `.public`: `ResearchTrace` already guarantees that no prompt,
/// search result, key or provider error text reaches a message, and redacting stage
/// names and durations would make the log useless for the bug reports it exists for.
struct OSLogSink: LogSink {
    private let logger = Logger(subsystem: AppIdentity.bundleIdentifier, category: "research")

    func write(_ level: LogLevel, _ message: String) {
        switch level {
        case .info: logger.info("\(message, privacy: .public)")
        case .warning: logger.warning("\(message, privacy: .public)")
        }
    }
}
