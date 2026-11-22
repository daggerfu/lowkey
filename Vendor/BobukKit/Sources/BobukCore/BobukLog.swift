// Logging helper. On macOS uses OSLog (available since 10.12); on Linux falls back to stderr.
import Foundation
#if canImport(OSLog)
import OSLog

public enum BobukLog {
    public static func logger(_ category: String, subsystem: String? = nil) -> OSLog {
        OSLog(subsystem: subsystem ?? Bundle.main.bundleIdentifier ?? ProcessInfo.processInfo.processName,
              category: category)
    }
}
#else
// Linux has no unified logging: a tiny stderr stand-in keeps the call sites source-compatible.
public enum BobukLog {
    public struct Logger {
        public let category: String
        public func info(_ message: String) { fputs("[\(category)] \(message)\n", stderr) }
        public func debug(_ message: String) { fputs("[\(category)] \(message)\n", stderr) }
        public func error(_ message: String) { fputs("[\(category)] \(message)\n", stderr) }
    }

    public static func logger(_ category: String, subsystem: String? = nil) -> Logger {
        Logger(category: category)
    }
}
#endif
