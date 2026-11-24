import Foundation

struct AppRecord: Identifiable, Hashable {
    let id: Int
    let bundleID: String
    let name: String
    let developer: String
    let iconURL: URL?
    let version: String
    let fileSizeBytes: Int64?
    let minimumOSVersion: String?
}

enum DownloadStatus: String, Equatable {
    case waiting = "Waiting"
    case authenticating = "Authenticating"
    case fetchingMetadata = "Fetching Metadata"
    case downloading = "Downloading"
    case verifying = "Verifying"
    case completed = "Completed"
    case failed = "Failed"
    case cancelled = "Cancelled"
}

struct DownloadTask: Identifiable {
    let id: UUID
    let app: AppRecord
    var status: DownloadStatus
    var progress: Double
    var downloadedBytes: Int64
    var totalBytes: Int64
    var fileURL: URL?
    var errorMessage: String?
}

enum AuthPhase: Equatable {
    case signedOut
    case waitingFor2FA
    case authenticating
    case signedIn
}

enum IPAForgeVersion {
    static func displayValue(
        shortVersion: String? = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    ) -> String {
        let version = shortVersion?.trimmingCharacters(in: .whitespacesAndNewlines)
        return version?.isEmpty == false ? version! : "1.0.0"
    }
}
