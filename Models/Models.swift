import Foundation

struct AppRecord: Identifiable, Hashable, Sendable {
    let id: Int
    let bundleID: String
    let name: String
    let developer: String
    let iconURL: URL?
    let version: String
    let fileSizeBytes: Int64?
    let minimumOSVersion: String?
    let price: Double?

    init(
        id: Int,
        bundleID: String,
        name: String,
        developer: String,
        iconURL: URL?,
        version: String,
        fileSizeBytes: Int64?,
        minimumOSVersion: String?,
        price: Double? = nil
    ) {
        self.id = id
        self.bundleID = bundleID
        self.name = name
        self.developer = developer
        self.iconURL = iconURL
        self.version = version
        self.fileSizeBytes = fileSizeBytes
        self.minimumOSVersion = minimumOSVersion
        self.price = price
    }
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

    var localizationKey: String {
        switch self {
        case .waiting: return "Waiting to download…"
        case .authenticating: return "Authenticating with the App Store…"
        case .fetchingMetadata: return "Fetching app metadata…"
        case .downloading: return "Downloading from the App Store…"
        case .verifying: return "Verifying IPA structure and integrity…"
        case .completed: return "Download completed"
        case .failed: return "Download failed"
        case .cancelled: return "Download cancelled"
        }
    }

    var isInProgress: Bool {
        switch self {
        case .waiting, .authenticating, .fetchingMetadata, .downloading, .verifying:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }
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
        return version?.isEmpty == false ? version! : "Unknown"
    }
}
