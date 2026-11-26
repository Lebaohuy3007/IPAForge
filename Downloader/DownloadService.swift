import Foundation
import Combine

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    private let provider: AppStoreDownloadProviding
    private let exportService: ExportService
    private let ipaInspector: IPAInspector
    private var workerTasks: [UUID: Task<Void, Never>] = [:]

    init(
        provider: AppStoreDownloadProviding = AppStoreDownloadService(),
        exportService: ExportService = ExportService(),
        ipaInspector: IPAInspector = IPAInspector()
    ) {
        self.provider = provider
        self.exportService = exportService
        self.ipaInspector = ipaInspector
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
            totalBytes: 0,
            fileURL: nil,
            errorMessage: nil
        ))
        workerTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(taskID: taskID, app: app)
        }
        return false
    }

    private func performDownload(taskID: UUID, app: AppRecord) async {
        defer { workerTasks[taskID] = nil }
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let fileManager = FileManager.default
        let taskDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("IPAForgeDownloads", isDirectory: true)
            .appendingPathComponent(taskID.uuidString, isDirectory: true)
        let destination = taskDirectory.appendingPathComponent("\(safeFilename(app.name))-\(app.id).ipa")
        let savedFile = documents.appendingPathComponent(
            "\(safeFilename(app.name))-\(app.id)-\(taskID.uuidString).ipa"
        )
        do {
            try Task.checkCancellation()
            try fileManager.createDirectory(at: taskDirectory, withIntermediateDirectories: true)
            update(taskID: taskID, status: .authenticating, errorMessage: nil)
            update(taskID: taskID, status: .fetchingMetadata, errorMessage: nil)
            let url = try await provider.download(app: app, destination: destination) { [weak self] downloaded, total in
                Task { @MainActor in
                    self?.reportDownloadProgress(taskID: taskID, downloaded: downloaded, total: total)
                }
            }
            try Task.checkCancellation()
            guard url.standardizedFileURL == destination.standardizedFileURL else {
                throw AppStoreDownloadError.unexpectedDownloadLocation
            }
            update(taskID: taskID, status: .verifying, errorMessage: nil)
            _ = try await inspectOffMainActor(url)
            try exportService.validate(url)
            try Task.checkCancellation()
            try fileManager.createDirectory(at: documents, withIntermediateDirectories: true)
            try fileManager.moveItem(at: url, to: savedFile)
            try exportService.validate(savedFile)
            try? fileManager.removeItem(at: taskDirectory)
            let actualSize = try? savedFile.resourceValues(forKeys: [.fileSizeKey]).fileSize
            guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
            tasks[index].status = .completed
            tasks[index].progress = 1
            if let actualSize {
                tasks[index].downloadedBytes = Int64(actualSize)
                tasks[index].totalBytes = Int64(actualSize)
            }
            tasks[index].fileURL = savedFile
        } catch is CancellationError {
            update(taskID: taskID, status: .cancelled, errorMessage: nil)
            try? fileManager.removeItem(at: taskDirectory)
            try? fileManager.removeItem(at: savedFile)
        } catch {
            if Task.isCancelled {
                update(taskID: taskID, status: .cancelled, errorMessage: nil)
            } else {
                update(taskID: taskID, status: .failed, errorMessage: error.localizedDescription)
            }
            try? fileManager.removeItem(at: taskDirectory)
            try? fileManager.removeItem(at: savedFile)
        }
    }

    private func inspectOffMainActor(_ url: URL) async throws -> IPAInspection {
        let inspector = ipaInspector
        let inspectionTask = Task.detached(priority: .utility) {
            try inspector.inspect(url)
        }
        return try await withTaskCancellationHandler {
            try await inspectionTask.value
        } onCancel: {
            inspectionTask.cancel()
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
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].status.isInProgress else { return }
        let received = max(downloaded, 0)
        tasks[index].status = .downloading
        tasks[index].downloadedBytes = received
        if total > 0 {
            tasks[index].totalBytes = total
            tasks[index].progress = min(Double(received) / Double(total), 1)
        } else {
            tasks[index].totalBytes = 0
            tasks[index].progress = 0
        }
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].status.isInProgress else { return }
        workerTasks[taskID]?.cancel()
        tasks[index].status = .cancelled
    }

    /// Starts a fresh task for a failed or cancelled download. The new task gets its own
    /// temporary path so a stale provider attempt cannot overwrite the retry's output.
    @discardableResult
    func retry(taskID: UUID) -> Bool {
        guard let task = tasks.first(where: { $0.id == taskID }),
              (task.status == .failed || task.status == .cancelled) else { return false }
        return !start(app: task.app)
    }

    func remove(taskID: UUID) throws {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        workerTasks[taskID]?.cancel()
        workerTasks[taskID] = nil
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
