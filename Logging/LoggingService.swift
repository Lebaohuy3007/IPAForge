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
    @Published private(set) var loginEntries: [LogEntry] = []

    func log(_ level: LogLevel, _ message: String) {
        entries.append(makeEntry(level, message))
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    func logLogin(_ level: LogLevel, _ message: String) {
        loginEntries.append(makeEntry(level, message))
        if loginEntries.count > 500 {
            loginEntries.removeFirst(loginEntries.count - 500)
        }
    }

    func clear() {
        entries.removeAll()
    }

    func clearLogin() {
        loginEntries.removeAll()
    }

    var text: String {
        entries.map(\.formatted).joined(separator: "\n")
    }

    private func makeEntry(_ level: LogLevel, _ message: String) -> LogEntry {
        LogEntry(date: Date(), level: level, message: LogSanitizer.sanitize(message))
    }
}

enum LogSanitizer {
    static func sanitize(_ text: String) -> String {
        let patterns = [
            #"(?i)"?(password|passcode|2fa|verification code|session token|session_token|token|cookie)"?\s*[:=]\s*"?[^,\s"}]+"#,
            #"(?i)"?(x-apple-(?:i-[a-z0-9-]+|locale)|x-mme-[a-z0-9-]+|adi[_.-]?(?:pb|blob)|anisette[_ -]?(?:data|identity)|identifier)"?\s*[:=]\s*"?[^,\s"}]+"#,
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
