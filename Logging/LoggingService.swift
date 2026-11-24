import Foundation
import Combine

enum LogLevel: String, Equatable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case success = "SUCCESS"
}

struct LogEntry: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: LogLevel
    let message: String

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return "[\(formatter.string(from: date))] [\(level.rawValue)] \(message)"
    }
}

@MainActor
final class LoggingService: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []

    func log(_ level: LogLevel, _ message: String) {
        entries.append(LogEntry(date: Date(), level: level, message: LogSanitizer.sanitize(message)))
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    func clear() {
        entries.removeAll()
    }

    var text: String {
        entries.map(\.formatted).joined(separator: "\n")
    }
}

enum LogSanitizer {
    static func sanitize(_ text: String) -> String {
        let patterns = [
            #"(?i)\b(password|passcode|2fa|verification code|token|cookie)\s*[:=]\s*\S+"#,
            #"(?i)\bBearer\s+[A-Za-z0-9._~-]+"#
        ]
        return patterns.reduce(text) { result, pattern in
            result.replacingOccurrences(
                of: pattern,
                with: "[REDACTED]",
                options: .regularExpression
            )
        }
    }
}
