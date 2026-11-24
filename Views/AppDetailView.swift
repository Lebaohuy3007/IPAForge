import SwiftUI

struct AppDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    let app: AppRecord

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    AsyncImage(url: app.iconURL) { image in
                        image.resizable().scaledToFill()
                    } placeholder: {
                        Color.gray.opacity(0.2)
                    }
                    .frame(width: 96, height: 96)
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    VStack(alignment: .leading) {
                        Text(app.name).font(.title2.bold())
                        Text(app.developer).foregroundStyle(.secondary)
                    }
                }
                DetailRow(title: "Bundle ID", value: app.bundleID)
                DetailRow(title: "Latest Version", value: app.version)
                DetailRow(title: "App ID", value: String(app.id))
                if let size = app.fileSizeBytes {
                    DetailRow(
                        title: "Size",
                        value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                    )
                }
                Section("Old Version") {
                    Text("No verified old-version metadata is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button {
                    environment.downloads.start(app: app)
                } label: {
                    Label("Tải xuống", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, alignment: .leading)
                Text("Downloads require Apple Account entitlement. IPA delivery is not implemented in this build.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct DetailRow: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
