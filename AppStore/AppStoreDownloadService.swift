import Foundation

enum AppStoreDownloadError: LocalizedError, Sendable {
    case directEngineUnavailable
    case unexpectedDownloadLocation

    var errorDescription: String? {
        switch self {
        case .directEngineUnavailable:
            return "App Store engine trực tiếp chưa được tích hợp vào ứng dụng."
        case .unexpectedDownloadLocation:
            return "The download provider returned a file outside its assigned temporary location."
        }
    }
}

protocol AppStoreDownloadProviding: Sendable {
    /// Providers must honor task cancellation, cancel the underlying network task, and stop writing
    /// before returning or throwing. Progress values must come from the actual transfer.
    func download(
        app: AppRecord,
        destination: URL,
        progress: @escaping @Sendable (Int64, Int64) -> Void
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
        progress: @escaping @Sendable (Int64, Int64) -> Void
    ) async throws -> URL {
        _ = (app, destination, progress)
        throw AppStoreDownloadError.directEngineUnavailable
    }
}
