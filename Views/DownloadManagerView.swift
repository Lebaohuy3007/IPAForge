import SwiftUI

struct DownloadManagerView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List(environment.downloads.tasks) { task in
                NavigationLink(value: task.id) {
                    DownloadRow(task: task)
                }
            }
            .overlay {
                if environment.downloads.tasks.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle").font(.largeTitle)
                        Text("No Downloads").font(.headline)
                        Text("Download activity will appear here.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationDestination(for: UUID.self) { taskID in
                if let task = environment.downloads.tasks.first(where: { $0.id == taskID }) {
                    DownloadDetailView(task: task)
                }
            }
            .navigationTitle("Downloads")
        }
    }
}

private struct DownloadRow: View {
    let task: DownloadTask

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading) {
                    Text(task.app.name).font(.headline)
                    Text("v\(task.app.version)").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(task.status.rawValue).font(.caption).foregroundStyle(.secondary)
            }
            ProgressView(value: task.progress)
            Text(task.errorMessage ?? "\(Int(task.progress * 100))%")
                .font(.caption)
                .foregroundStyle(task.errorMessage == nil ? .secondary : .red)
        }
        .padding(.vertical, 4)
    }
}
