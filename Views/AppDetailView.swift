import SwiftUI

struct AppDetailView: View {
    @State private var isShowingDownloadNotice = false
    @State private var isShowingOldVersions = false
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
                Button {
                    isShowingOldVersions = true
                } label: {
                    Label("Phiên bản cũ", systemImage: "clock.arrow.circlepath")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)

                Button {
                    isShowingDownloadNotice = true
                } label: {
                    Label("Tải xuống", systemImage: "arrow.down.to.line")
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Thông báo", isPresented: $isShowingDownloadNotice) {
            Button("Hủy", role: .cancel) { }
            Button("OK") { }
        } message: {
            Text("Chưa làm giao diện tải IPA, vui lòng đợi bản mới")
        }
        .sheet(isPresented: $isShowingOldVersions) {
            NavigationStack {
                List {
                    Label("Chưa có dữ liệu phiên bản cũ được xác minh.", systemImage: "clock.arrow.circlepath")
                        .foregroundStyle(.secondary)
                }
                .navigationTitle("Phiên bản cũ")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Đóng") { isShowingOldVersions = false }
                    }
                }
            }
        }
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
