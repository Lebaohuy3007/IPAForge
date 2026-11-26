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

        logger.log(.info, "Experiment A | Experiment Started | Public App Store API.")
        logger.log(.info, "Experiment A | Authentication Mode: anonymous.")
        logger.log(.warning, "Experiment A | App Store session unavailable; no account was used.")

        let knownFreeAppID = 375_380_948
        var checks: [AppStoreExperimentCheck] = []
        var searchHTTPStatus: Int?
        do {
            let results = try await appStore.search("Apple Store", country: "us") {
                searchHTTPStatus = $0
            }
            let app = results.first(where: { $0.id == knownFreeAppID })
            if let app, app.price == 0 {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Search",
                    status: .passed,
                    detail: "HTTP \(searchHTTPStatus.map(String.init) ?? "2xx"); found free app ID \(knownFreeAppID)."
                ))
                logger.log(.success, "Experiment A | Public Search | HTTP \(searchHTTPStatus.map(String.init) ?? "2xx") | PASS.")
            } else {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Search",
                    status: .failed,
                    detail: "HTTP \(searchHTTPStatus.map(String.init) ?? "2xx"); expected free app ID \(knownFreeAppID) was not returned."
                ))
                logger.log(.error, "Experiment A | Public Search | Expected free app was not returned.")
            }
        } catch {
            let detail = Self.safeFailureDetail(error, statusCode: searchHTTPStatus)
            checks.append(AppStoreExperimentCheck(name: "A · Search", status: .failed, detail: detail))
            logger.log(.error, "Experiment A | Public Search failed | \(detail).")
        }

        var metadataHTTPStatus: Int?
        do {
            let result = try await appStore.lookup(
                appID: knownFreeAppID,
                country: "us",
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
                logger.log(.success, "Experiment A | Public Metadata Request | HTTP \(metadataHTTPStatus.map(String.init) ?? "2xx") | PASS.")
            } else {
                checks.append(AppStoreExperimentCheck(
                    name: "A · Metadata",
                    status: .failed,
                    detail: "HTTP \(metadataHTTPStatus.map(String.init) ?? "2xx"); response lacked required app metadata."
                ))
                logger.log(.error, "Experiment A | Public Metadata Request | Required app metadata was missing.")
            }
        } catch {
            let detail = Self.safeFailureDetail(error, statusCode: metadataHTTPStatus)
            checks.append(AppStoreExperimentCheck(name: "A · Metadata", status: .failed, detail: detail))
            logger.log(.error, "Experiment A | Public Metadata Request failed | \(detail).")
        }

        checks.append(AppStoreExperimentCheck(
            name: "A · Binary access",
            status: .unsupported,
            detail: "Apple's documented public Search/Lookup API returns catalog metadata, not an IPA download URL."
        ))
        logger.log(.warning, "Experiment A | Binary access | NOT SUPPORTED by the documented public Search/Lookup API.")

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
        logger.log(.info, "Experiment A | IPA download and integrity | NOT TESTED; no public binary URL.")

        checks.append(AppStoreExperimentCheck(
            name: "B · Authentication",
            status: .blocked,
            detail: "Not attempted: no compliant iOS App Store authentication and device-identity provider is implemented. No credentials were entered."
        ))
        logger.log(.warning, "Experiment B | Authentication | NOT STARTED; iOS identity/authentication route is blocked. No credentials were requested or sent.")
        logger.log(.info, "Experiment B | 2FA, session restore, license, download, and IPA validation | NOT TESTED.")

        report = AppStoreExperimentReport(completedAt: Date(), checks: checks)
        logger.log(.info, "Experiment A final result | \(report?.summary ?? "not available")")
        logger.log(.warning, "Experiment B final result | BLOCKED before sign-in; no live authentication was attempted.")
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
