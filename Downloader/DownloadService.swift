import Foundation
import Combine

@MainActor
final class DownloadService: ObservableObject {
    @Published private(set) var tasks: [DownloadTask] = []

    func start(app: AppRecord) {
        tasks.append(DownloadTask(
            id: UUID(),
            app: app,
            status: .failed,
            progress: 0,
            downloadedBytes: 0,
            totalBytes: app.fileSizeBytes ?? 0,
            fileURL: nil,
            errorMessage: "IPA delivery is not implemented. No package download was attempted."
        ))
    }

    func cancel(taskID: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[index].status = .cancelled
    }
}
