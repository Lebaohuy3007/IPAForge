import SwiftUI

struct DownloadManagerView: View {
    @ObservedObject var downloads: DownloadService
    @State private var pendingDeleteID: UUID?
    @State private var deleteError: String?

    var body: some View {
        NavigationStack {
            List(downloads.tasks) { task in
                NavigationLink(value: task.id) {
                    DownloadRow(task: task)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        pendingDeleteID = task.id
                    } label: {
                        Label("Xoá", systemImage: "trash")
                    }
                }
            }
            .overlay {
                if downloads.tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").font(.largeTitle)
                        Text("Chưa có lượt tải").font(.headline)
                        Text("Ứng dụng bạn tải sẽ xuất hiện ở đây.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { taskID in
                DownloadDetailView(taskID: taskID, downloads: downloads)
            }
            .navigationTitle("iPA Downloader")
            .alert("Cảnh báo", isPresented: Binding(
                get: { pendingDeleteID != nil || deleteError != nil },
                set: { if !$0 { pendingDeleteID = nil; deleteError = nil } }
            )) {
                if deleteError != nil {
                    Button("OK", role: .cancel) { self.deleteError = nil }
                } else {
                    Button("Hủy", role: .cancel) { pendingDeleteID = nil }
                    Button("OK", role: .destructive) { deletePendingTask() }
                }
            } message: {
                Text(deleteError ?? "Bạn có chắc muốn xoá ứng dụng này ra khỏi máy bạn không?")
            }
        }
    }

    private func deletePendingTask() {
        guard let id = pendingDeleteID else { return }
        do {
            try downloads.remove(taskID: id)
            pendingDeleteID = nil
        } catch {
            pendingDeleteID = nil
            deleteError = error.localizedDescription
        }
    }
}

private struct DownloadRow: View {
    let task: DownloadTask

    var body: some View {
        HStack(spacing: 12) {
            appIcon(size: 54)
            VStack(alignment: .leading, spacing: 7) {
                Text(task.app.name).font(.headline).lineLimit(1)
                Text(task.app.developer).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
                if task.status.isInProgress {
                    ProgressView(value: task.progress)
                    Text(task.statusMessage)
                        .font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(task.progress * 100))%")
                        .font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(task.errorMessage ?? task.statusMessage)
                        .font(.caption).foregroundStyle(task.status == .failed ? .red : .secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func appIcon(size: CGFloat) -> some View {
        AsyncImage(url: task.app.iconURL) { image in
            image.resizable().scaledToFill()
        } placeholder: {
            RoundedRectangle(cornerRadius: 12).fill(.gray.opacity(0.2))
                .overlay { Image(systemName: "app.fill").foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
