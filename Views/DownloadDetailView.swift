import SwiftUI
import UIKit

struct DownloadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let taskID: UUID
    @ObservedObject var downloads: DownloadService
    @State private var shareItems: [URL] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?
    @State private var retryError: String?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        Group {
            if let task {
                Form {
                    Section {
                        HStack(spacing: 14) {
                            appIcon(task.app.iconURL)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(task.app.name).font(.headline)
                                Text(task.app.developer).foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    if task.status.isInProgress {
                        Section(task.statusMessage) {
                            if task.totalBytes > 0 {
                                ProgressView(value: task.progress)
                                Text("\(Int(task.progress * 100))%")
                                    .foregroundStyle(.secondary)
                                Text("\(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else {
                                ProgressView()
                                Text("\(ByteCountFormatter.string(fromByteCount: task.downloadedBytes, countStyle: .file)) downloaded · total unknown")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if let error = task.errorMessage {
                        Section("Trạng thái") {
                            Text(error).foregroundStyle(.secondary)
                        }
                    }
                    Section {
                        metadataRow("Version", task.app.version)
                        metadataRow("Size", appSize(task))
                        metadataRow("Minimum iOS", task.app.minimumOSVersion ?? "—")
                        metadataRow("Bundle ID", task.app.bundleID)
                        metadataRow("Đã giải mã", "Encrypted")
                    }
                    if let errorMessage {
                        Section("Lỗi chia sẻ") { Text(errorMessage).foregroundStyle(.red) }
                    }
                    if let retryError {
                        Section("Retry") { Text(retryError).foregroundStyle(.red) }
                    }
                    Section("Tùy chọn") {
                        if task.status.isInProgress {
                            Button(role: .destructive) {
                                downloads.cancel(taskID: task.id)
                            } label: {
                                Label("Cancel Download", systemImage: "xmark.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        if task.status == .failed || task.status == .cancelled {
                            Button {
                                if downloads.retry(taskID: task.id) {
                                    dismiss()
                                } else {
                                    retryError = "Could not start a retry. Check available storage."
                                }
                            } label: {
                                Label("Retry", systemImage: "arrow.clockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        if task.status == .completed, let fileURL = task.fileURL {
                            Button {
                                share(fileURL)
                            } label: {
                                Label("Export", systemImage: "square.and.arrow.up")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        Button(role: .destructive) {
                            isShowingDeleteConfirmation = true
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "arrow.down.circle").font(.largeTitle)
                    Text("Không tìm thấy lượt tải").font(.headline)
                }
                .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("iPA Downloader")
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: shareItems)
        }
        .alert("Cảnh báo", isPresented: $isShowingDeleteConfirmation) {
            Button("Hủy", role: .cancel) { }
            Button("OK", role: .destructive) { deleteTask() }
        } message: {
            Text("Bạn có chắc muốn xoá ứng dụng này ra khỏi máy bạn không?")
        }
    }

    private var task: DownloadTask? {
        downloads.tasks.first { $0.id == taskID }
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        LabeledContent(title, value: value)
            .textSelection(.enabled)
    }

    private func appSize(_ task: DownloadTask) -> String {
        if let size = task.app.fileSizeBytes {
            return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
        }
        if task.totalBytes > 0 {
            return ByteCountFormatter.string(fromByteCount: task.totalBytes, countStyle: .file)
        }
        return "—"
    }

    private func appIcon(_ url: URL?) -> some View {
        AsyncImage(url: url) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 14).fill(.gray.opacity(0.2))
                .overlay { Image(systemName: "app.fill").foregroundStyle(.secondary) }
        }
        .frame(width: 68, height: 68)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func share(_ url: URL) {
        do {
            shareItems = try environment.export.shareItems(for: url)
            showingShareSheet = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteTask() {
        do {
            try downloads.remove(taskID: taskID)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
