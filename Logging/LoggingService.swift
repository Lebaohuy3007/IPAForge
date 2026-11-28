import Foundation
import Combine

enum LogLevel: String, Equatable, Sendable {
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
    case success = "SUCCESS"
}

struct LogEntry: Identifiable, Equatable {
    let id: UUID
    let date: Date
    let level: LogLevel
    let message: String
    let correlationID: UUID?

    init(
        id: UUID = UUID(),
        date: Date,
        level: LogLevel,
        message: String,
        correlationID: UUID? = nil
    ) {
        self.id = id
        self.date = date
        self.level = level
        self.message = message
        self.correlationID = correlationID
    }

    var formatted: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        let correlation = correlationID.map { " [Correlation ID: \($0.uuidString)]" } ?? ""
        return "[\(formatter.string(from: date))] [\(level.rawValue)] [Event ID: \(id.uuidString)]\(correlation) \(message)"
    }
}

@MainActor
final class LoggingService: ObservableObject {
    @Published private(set) var entries: [LogEntry] = []
    @Published private(set) var loginEntries: [LogEntry] = []

    func log(_ level: LogLevel, _ message: String, correlationID: UUID? = nil) {
        entries.append(makeEntry(level, message, correlationID: correlationID))
        if entries.count > 500 {
            entries.removeFirst(entries.count - 500)
        }
    }

    func logLogin(_ level: LogLevel, _ message: String, correlationID: UUID? = nil) {
        loginEntries.append(makeEntry(level, message, correlationID: correlationID))
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

    private func makeEntry(_ level: LogLevel, _ message: String, correlationID: UUID?) -> LogEntry {
        LogEntry(
            date: Date(),
            level: level,
            message: LogSanitizer.sanitize(message),
            correlationID: correlationID
        )
    }
}

enum LogSanitizer {
    static func sanitize(_ text: String) -> String {
        let patterns = [
            #"(?i)"?(password(?:[_ -]?token)?|passcode|2fa|verification code|session[_ -]?token|auth(?:entication)?[_ -]?token|token|cookie|dsid|myacinfo|sinf)"?\s*[:=]\s*"?[^,\s"}]+"#,
            #"(?i)"?(x-apple-(?:i-[a-z0-9-]+|locale|amd(?:-m)?|actionsignature)|x-mme-[a-z0-9-]+|adi[_.-]?(?:pb|blob)|anisette[_ -]?(?:data|identity)|identifier)"?\s*[:=]\s*"?[^,\s"}]+"#,
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
