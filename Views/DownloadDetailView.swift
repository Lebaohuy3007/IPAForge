import SwiftUI
import UIKit

struct DownloadDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let task: DownloadTask
    @State private var shareItems: [URL] = []
    @State private var showingShareSheet = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Application") {
                Text(task.app.name)
                Text("Version \(task.app.version)")
            }
            Section("Progress") {
                Text(task.status.rawValue)
                ProgressView(value: task.progress)
                Text("\(Int(task.progress * 100))%")
            }
            if let error = task.errorMessage {
                Section("Status") { Text(error).foregroundStyle(.secondary) }
            }
            if task.status == .completed, let fileURL = task.fileURL {
                Section("Download Completed") {
                    Text("File: \(fileURL.lastPathComponent)")
                    if let values = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
                       let size = values[.size] as? NSNumber {
                        Text("Size: \(ByteCountFormatter.string(fromByteCount: size.int64Value, countStyle: .file))")
                    }
                    Text("Path: \(fileURL.path)")
                        .font(.caption)
                        .textSelection(.enabled)
                    Button("Share IPA") { share(fileURL) }
                    Button("Save to Files") { share(fileURL) }
                }
            } else if task.status == .waiting || task.status == .downloading {
                Section {
                    Button("Cancel Download", role: .destructive) {
                        environment.downloads.cancel(taskID: task.id)
                    }
                }
            }
            if let errorMessage {
                Section("Export Error") { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle("Download")
        .sheet(isPresented: $showingShareSheet) {
            ActivityView(activityItems: shareItems)
        }
    }

    private func share(_ url: URL) {
        do {
            shareItems = try environment.export.shareItems(for: url)
            showingShareSheet = true
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
