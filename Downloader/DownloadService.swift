import Foundation
import Combine

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    private let provider: AppStoreDownloadProviding
    private let exportService: ExportService
    private let ipaInspector: IPAInspecting
    private let logger: LoggingService?
    private var workerTasks: [UUID: Task<Void, Never>] = [:]
    private var lastProgressMilestone: [UUID: Int] = [:]

    init(
        provider: AppStoreDownloadProviding = AppStoreDownloadService(),
        exportService: ExportService = ExportService(),
        ipaInspector: IPAInspecting = IPAInspector(),
        logger: LoggingService? = nil
    ) {
        self.provider = provider
        self.exportService = exportService
        self.ipaInspector = ipaInspector
        self.logger = logger
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
        logger?.log(.info, "Download Started | App ID \(app.id).", correlationID: taskID)
        workerTasks[taskID] = Task { [weak self] in
            guard let self else { return }
            await self.performDownload(taskID: taskID, app: app)
        }
        return false
    }

    private func performDownload(taskID: UUID, app: AppRecord) async {
        defer {
            workerTasks[taskID] = nil
            lastProgressMilestone[taskID] = nil
        }
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
            try Task.checkCancellation()
            try exportService.validate(url)
            try Task.checkCancellation()
            logger?.log(
                .success,
                "IPA structure, app metadata, and ZIP CRC checks | PASS | Apple code signature | NOT VERIFIED | App ID \(app.id).",
                correlationID: taskID
            )
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
            logger?.log(.success, "Download Completed | App ID \(app.id) | IPA saved after validation.", correlationID: taskID)
        } catch is CancellationError {
            update(taskID: taskID, status: .cancelled, errorMessage: nil)
            logger?.log(.warning, "Download Cancelled | App ID \(app.id).", correlationID: taskID)
            try? fileManager.removeItem(at: taskDirectory)
            try? fileManager.removeItem(at: savedFile)
        } catch {
            if Task.isCancelled {
                update(taskID: taskID, status: .cancelled, errorMessage: nil)
                logger?.log(.warning, "Download Cancelled | App ID \(app.id).", correlationID: taskID)
            } else {
                update(taskID: taskID, status: .failed, errorMessage: error.localizedDescription)
                logger?.log(
                    .error,
                    "Download Failed | \(failureSummary(for: error)) | App ID \(app.id).",
                    correlationID: taskID
                )
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

    private func failureSummary(for error: Error) -> String {
        if error is IPAInspectionError { return "IPA verification failed" }
        if let urlError = error as? URLError { return "connection error code \(urlError.code.rawValue)" }
        if let storeError = error as? AppStoreServiceError {
            switch storeError {
            case .invalidResponse: return "invalid public Store response"
            case .httpStatus(let status): return "HTTP \(status)"
            }
        }
        switch error as? AppStoreDownloadError {
        case .directEngineUnavailable?: return "internal engine unavailable"
        case .unexpectedDownloadLocation?: return "download provider returned an unexpected file"
        case nil: return "download provider error"
        }
    }

    var availableStorageBytes: Int64? {
        let values = try? URL(fileURLWithPath: "/")
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values?.volumeAvailableCapacityForImportantUsage
    }

    func reportDownloadProgress(taskID: UUID, downloaded: Int64, total: Int64) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }),
              tasks[index].status.isInProgress,
              tasks[index].status != .verifying else { return }
        let received = max(downloaded, 0)
        tasks[index].status = .downloading
        tasks[index].downloadedBytes = received
        if total > 0 {
            tasks[index].totalBytes = total
            tasks[index].progress = min(Double(received) / Double(total), 1)
            let milestone = min(Int(Double(received) / Double(total) * 10), 10) * 10
            if milestone >= 10, milestone > lastProgressMilestone[taskID, default: 0] {
                lastProgressMilestone[taskID] = milestone
                logger?.log(
                    .info,
                    "Download Progress | App ID \(tasks[index].app.id) | \(received) / \(total) bytes | \(milestone)%.",
                    correlationID: taskID
                )
            }
        } else {
            tasks[index].totalBytes = 0
            tasks[index].progress = 0
            if received > 0, lastProgressMilestone[taskID] == nil {
                lastProgressMilestone[taskID] = -1
                logger?.log(
                    .info,
                    "Download Progress | App ID \(tasks[index].app.id) | \(received) bytes received | total unknown.",
                    correlationID: taskID
                )
            }
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
