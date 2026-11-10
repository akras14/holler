import os

/// Writes to the macOS system log, so a dictation that went wrong can be traced afterwards:
///
///     log show --last 1h --predicate 'subsystem == "com.alexkras.holler"'
///
/// Messages say what happened, never what was said or typed.
enum Log {
    static let subsystem = "com.alexkras.holler"

    static func writer(_ category: String) -> (String) -> Void {
        let logger = Logger(subsystem: subsystem, category: category)
        // Notice is the lowest level macOS keeps on disk.
        return { logger.notice("\($0, privacy: .public)") }
    }
}
