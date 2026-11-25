import Foundation
import Combine

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    private let provider: AppStoreDownloadProviding
    private let exportService: ExportService

    init(
        provider: AppStoreDownloadProviding = AppStoreDownloadService(),
        exportService: ExportService = ExportService()
    ) {
        self.provider = provider
        self.exportService = exportService
    }

    /// Returns true when the app cannot fit in the currently available storage.
    @discardableResult
    func start(app: AppRecord) -> Bool {
        if let required = app.fileSizeBytes,
           let available = availableStorageBytes,
           required > available {
            return true
        }
        let taskID = UUID()
        tasks.append(DownloadTask(
            id: taskID,
            app: app,
            status: .waiting,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: app.fileSizeBytes ?? 0,
            fileURL: nil,
            errorMessage: nil
        ))
        Task { [weak self] in
            await self?.performDownload(taskID: taskID, app: app)
        }
        return false
    }

    private func performDownload(taskID: UUID, app: AppRecord) async {
        update(taskID: taskID, status: .authenticating, errorMessage: nil)
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let destination = documents.appendingPathComponent("\(safeFilename(app.name))-\(app.id).ipa")
        do {
            update(taskID: taskID, status: .fetchingMetadata, errorMessage: nil)
            let url = try await provider.download(app: app, destination: destination) { [weak self] downloaded, total in
                Task { @MainActor in
                    self?.reportDownloadProgress(taskID: taskID, downloaded: downloaded, total: total)
                }
            }
            update(taskID: taskID, status: .verifying, errorMessage: nil)
            try exportService.validate(url)
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].status = .completed
            tasks[index].progress = 1
            tasks[index].downloadedBytes = tasks[index].totalBytes
            tasks[index].fileURL = url
        } catch is CancellationError {
            update(taskID: taskID, status: .cancelled, errorMessage: nil)
            try? FileManager.default.removeItem(at: destination)
        } catch {
            update(taskID: taskID, status: .failed, errorMessage: error.localizedDescription)
            try? FileManager.default.removeItem(at: destination)
        }
    }

    private func update(taskID: UUID, status: DownloadStatus, errorMessage: String?) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = status
        tasks[index].errorMessage = errorMessage
    }

    private func safeFilename(_ value: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*\u{0000}")
        let result = value.components(separatedBy: invalid).joined(separator: "-")
        return result.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "app" : result
    }

    var availableStorageBytes: Int64? {
        let values = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func reportDownloadProgress(taskID: UUID, downloaded: Int64, total: Int64) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }), total > 0 else { return }
        let fraction = min(max(Double(downloaded) / Double(total), 0), 1)
        tasks[index].status = .downloading
        tasks[index].downloadedBytes = downloaded
        tasks[index].totalBytes = total
        tasks[index].progress = 0.01 + fraction * 0.98
    }

    func reportSavingProgress(taskID: UUID, fraction: Double) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .verifying
        tasks[index].progress = 0.99 + min(max(fraction, 0), 1) * 0.01
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
    }

    func remove(taskID: UUID) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        if let fileURL = tasks[index].fileURL {
            let documentsDirectory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                .standardizedFileURL
            let fileToRemove = fileURL.standardizedFileURL
            guard fileToRemove.path.hasPrefix(documentsDirectory.path + "/") else {
                throw CocoaError(.fileWriteNoPermission)
            }
            try FileManager.default.removeItem(at: fileToRemove)
        }
        tasks.remove(at: index)
    }
}
