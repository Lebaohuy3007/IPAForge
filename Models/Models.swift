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

    var message: String {
        switch self {
        case .waiting: return "Đang chờ tải..."
        case .authenticating: return "Đang xác thực tài khoản App Store..."
        case .fetchingMetadata: return "Đang lấy thông tin ứng dụng..."
        case .downloading: return "Đang tải ứng dụng trên App Store..."
        case .verifying: return "Đang lưu tệp IPA..."
        case .completed: return "Đã tải xong"
        case .failed: return "Tải thất bại"
        case .cancelled: return "Đã hủy"
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

    var statusMessage: String {
        status == .verifying ? "Đang lưu \(app.name).ipa..." : status.message
    }
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
