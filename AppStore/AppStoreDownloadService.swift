import Foundation

enum AppStoreDownloadError: LocalizedError {
    case directEngineUnavailable

    var errorDescription: String? {
        switch self {
        case .directEngineUnavailable:
            return "App Store engine trực tiếp chưa được tích hợp vào ứng dụng."
        }
    }
}

protocol AppStoreDownloadProviding {
    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> URL
}

/// Boundary for an in-process ipatool/Crumb-compatible engine.
/// The implementation must perform Store authentication, SAP signing,
/// license acquisition and FairPlay package download inside the app.
struct AppStoreDownloadService: AppStoreDownloadProviding {
    init() {}

    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = (app, destination, progress)
        throw AppStoreDownloadError.directEngineUnavailable
    }
}
