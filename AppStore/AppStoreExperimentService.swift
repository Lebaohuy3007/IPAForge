import Foundation
import Combine

enum AppStoreExperimentStatus: String, Equatable {
    case passed = "PASS"
    case failed = "FAIL"
    case unsupported = "NOT SUPPORTED"
    case blocked = "BLOCKED"
    case notTested = "NOT TESTED"
}

struct AppStoreExperimentCheck: Identifiable, Equatable {
    let name: String
    let status: AppStoreExperimentStatus
    let detail: String

    var id: String { name }
}

struct AppStoreExperimentReport: Equatable {
    let completedAt: Date
    let checks: [AppStoreExperimentCheck]

    var summary: String {
        let searchPassed = checks.first(where: { $0.name == "A · Search" })?.status == .passed
        let metadataPassed = checks.first(where: { $0.name == "A · Metadata" })?.status == .passed
        let key = searchPassed && metadataPassed
            ? "Experiment A: public search and metadata passed; no public IPA download was found."
            : "Experiment A: public metadata test did not fully pass."
        return key
    }
}

@MainActor
final class AppStoreExperimentService: ObservableObject {
    @Published private(set) var report: AppStoreExperimentReport?
    @Published private(set) var isRunning = false

    private let appStore: AppStoreService
    private let logger: LoggingService

    init(appStore: AppStoreService, logger: LoggingService) {
        self.appStore = appStore
        self.logger = logger
    }

    func run() async {
        guard !isRunning else { return }
        isRunning = true
        defer { isRunning = false }
        let correlationID = UUID()

        log(.info, "Experiment A | Engine: Public App Store API | Stage: Initialization | Result: PASS.", correlationID: correlationID)
        log(.info, "Experiment A | Authentication Mode: anonymous.", correlationID: correlationID)
        log(.warning, "Experiment A | App Store session unavailable; no account was used.", correlationID: correlationID)

        let knownFreeAppID = 375_380_948
        var checks: [AppStoreExperimentCheck] = []
        var searchHTTPStatus: Int?
        var searchDiagnostics: AppStoreRequestDiagnostics?
        do {
            let results = try await appStore.search(
                "Apple Store",
                country: "us",
                onDiagnostics: { searchDiagnostics = $0 },
                onHTTPStatus: { searchHTTPStatus = $0 }
            )
            let app = results.first(where: { $0.id == knownFreeAppID })
            if let app, app.price == 0 {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Search",
                    status: .passed,
                    detail: "HTTP \(searchHTTPStatus.map(String.init) ?? "2xx"); found free app ID \(knownFreeAppID)."
                ))
                logNetworkDiagnostics(
                    searchDiagnostics,
                    stage: "Public Search",
                    parsing: "PASS",
                    validation: "PASS",
                    result: "PASS",
                    reason: "Expected free app ID \(knownFreeAppID) was found.",
                    nextAction: "None.",
                    correlationID: correlationID
                )
            } else {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Search",
                    status: .failed,
                    detail: "HTTP \(searchHTTPStatus.map(String.init) ?? "2xx"); expected free app ID \(knownFreeAppID) was not returned."
                ))
                logNetworkDiagnostics(
                    searchDiagnostics,
                    stage: "Public Search",
                    parsing: "PASS",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "Expected free app ID \(knownFreeAppID) was not returned as a free app.",
                    nextAction: "Check the selected storefront and current catalog listing.",
                    correlationID: correlationID
                )
            }
        } catch {
            let detail = Self.safeFailureDetail(error, statusCode: searchHTTPStatus)
            checks.append(AppStoreExperimentCheck(name: "A · Search", status: .failed, detail: detail))
            logNetworkDiagnostics(
                searchDiagnostics,
                stage: "Public Search",
                parsing: error as? AppStoreServiceError == .invalidResponse ? "FAIL" : "NOT RUN",
                validation: "NOT RUN",
                result: "FAIL",
                reason: detail,
                nextAction: "Check the reported HTTP or network error before retrying.",
                correlationID: correlationID
            )
        }

        var metadataHTTPStatus: Int?
        var metadataDiagnostics: AppStoreRequestDiagnostics?
        do {
            let result = try await appStore.lookup(
                appID: knownFreeAppID,
                country: "us",
                onDiagnostics: { metadataDiagnostics = $0 },
                onHTTPStatus: { metadataHTTPStatus = $0 }
            )
            if let app = result.first,
               app.id == knownFreeAppID,
               !app.bundleID.isEmpty,
               app.version != "Unknown",
               app.price == 0 {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Metadata",
                    status: .passed,
                    detail: "HTTP \(metadataHTTPStatus.map(String.init) ?? "2xx"); \(app.name) v\(app.version), free."
                ))
                logNetworkDiagnostics(
                    metadataDiagnostics,
                    stage: "Metadata Lookup",
                    parsing: "PASS",
                    validation: "PASS",
                    result: "PASS",
                    reason: "Bundle ID, version, and free price were present.",
                    nextAction: "None.",
                    correlationID: correlationID
                )
            } else {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Metadata",
                    status: .failed,
                    detail: "HTTP \(metadataHTTPStatus.map(String.init) ?? "2xx"); response lacked required app metadata."
                ))
                logNetworkDiagnostics(
                    metadataDiagnostics,
                    stage: "Metadata Lookup",
                    parsing: "PASS",
                    validation: "FAIL",
                    result: "FAIL",
                    reason: "Response did not include all required metadata for the expected free app.",
                    nextAction: "Inspect the current catalog response and required fields.",
                    correlationID: correlationID
                )
            }
        } catch {
            let detail = Self.safeFailureDetail(error, statusCode: metadataHTTPStatus)
            checks.append(AppStoreExperimentCheck(name: "A · Metadata", status: .failed, detail: detail))
            logNetworkDiagnostics(
                metadataDiagnostics,
                stage: "Metadata Lookup",
                parsing: error as? AppStoreServiceError == .invalidResponse ? "FAIL" : "NOT RUN",
                validation: "NOT RUN",
                result: "FAIL",
                reason: detail,
                nextAction: "Check the reported HTTP or network error before retrying.",
                correlationID: correlationID
            )
        }

        checks.append(AppStoreExperimentCheck(
            name: "A · Binary access",
            status: .unsupported,
            detail: "Apple's documented public Search/Lookup API returns catalog metadata, not an IPA download URL."
        ))
        log(.warning, "Experiment A | Stage: Binary access | NOT_SUPPORTED by the documented public Search/Lookup API.", correlationID: correlationID)

        checks.append(AppStoreExperimentCheck(
            name: "A · IPA download",
            status: .notTested,
            detail: "No documented public binary endpoint was available to test."
        ))
        checks.append(AppStoreExperimentCheck(
            name: "A · IPA integrity",
            status: .notTested,
            detail: "No IPA was obtained; IPAInspector was not run for this experiment."
        ))
        log(.info, "Experiment A | Stage: IPA download and integrity | NOT_TESTED; no public binary URL.", correlationID: correlationID)

        checks.append(AppStoreExperimentCheck(
            name: "B · Authentication",
            status: .blocked,
            detail: "Not attempted: no compliant iOS App Store authentication and device-identity provider is implemented. No credentials were entered."
        ))
        log(.warning, "Experiment B | Stage: Authentication | BLOCKED before sign-in. No credentials were requested or sent.", correlationID: correlationID)
        log(.info, "Experiment B | 2FA, session restore, license acquisition, binary download, and IPA validation | NOT_TESTED.", correlationID: correlationID)

        report = AppStoreExperimentReport(completedAt: Date(), checks: checks)
        log(.info, "Experiment A final result | \(report?.summary ?? "not available")", correlationID: correlationID)
        log(.warning, "Experiment B final result | BLOCKED before sign-in; no live authentication was attempted.", correlationID: correlationID)
    }

    private func log(_ level: LogLevel, _ message: String, correlationID: UUID) {
        logger.log(level, message, correlationID: correlationID)
    }

    private func logNetworkDiagnostics(
        _ diagnostics: AppStoreRequestDiagnostics?,
        stage: String,
        parsing: String,
        validation: String,
        result: String,
        reason: String,
        nextAction: String,
        correlationID: UUID
    ) {
        let level: LogLevel = result == "PASS" ? .success : .error
        let details = diagnostics?.activityLogMessage(
            engine: "Public App Store API",
            stage: stage,
            parsing: parsing,
            validation: validation,
            result: result,
            reason: reason,
            nextAction: nextAction
        ) ?? "Engine: Public App Store API | Stage: \(stage) | Method: GET | Endpoint: N/A | HTTP Status: N/A | Duration: N/A | Response Type: N/A | Response Size: N/A | Redirected: N/A | Retry Count: 0 | Retry-After: N/A | Server Request ID: N/A | Parsing: \(parsing) | Validation: \(validation) | Error Domain/Code: N/A | Result: \(result) | Reason: \(reason) | Next Action: \(nextAction)"
        let message = "Experiment A | \(details)"
        log(level, message, correlationID: correlationID)
    }

    private static func safeFailureDetail(_ error: Error, statusCode: Int?) -> String {
        if let urlError = error as? URLError {
            return "connection error \(urlError.code.rawValue)"
        }
        if let serviceError = error as? AppStoreServiceError {
            switch serviceError {
            case .invalidResponse:
                return "HTTP \(statusCode.map(String.init) ?? "unknown"); invalid public API response"
            case .httpStatus(let status):
                return "HTTP \(status)"
            }
        }
        if let statusCode {
            return "HTTP \(statusCode)"
        }
        return "request failed (\(String(describing: type(of: error))))"
    }
}
