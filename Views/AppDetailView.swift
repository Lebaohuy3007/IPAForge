import SwiftUI

struct AppDetailView: View {
    @State private var isShowingOldVersions = false
    @State private var isShowingStorageAlert = false
    @State private var isShowingDecryptionNotice = false
    @EnvironmentObject private var environment: AppEnvironment
    let app: AppRecord
    let onDownloadStarted: () -> Void

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
                VStack(spacing: 12) {
                    Text("Metadata")
                        .font(.title3.bold())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    metadataRow("Latest Version", app.version)
                    metadataRow("Size", appSize)
                    metadataRow("Minimum iOS", app.minimumOSVersion ?? "—")
                    metadataRow("Bundle ID", app.bundleID)
                }
                .padding(.vertical, 4)

                Text("Download")
                    .font(.title3.bold())

                Button {
                    isShowingOldVersions = true
                } label: {
                    Label("Phiên bản cũ", systemImage: "clock.arrow.circlepath")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button {
                    if environment.downloads.start(app: app) {
                        isShowingStorageAlert = true
                    } else {
                        onDownloadStarted()
                    }
                } label: {
                    Label("Tải xuống IPA", systemImage: "arrow.down.to.line")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

                Button {
                    isShowingDecryptionNotice = true
                } label: {
                    Label("Tải xuống với giải mã hoá", systemImage: "lock")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
                .alert("Thông báo", isPresented: $isShowingDecryptionNotice) {
                    Button("Huỷ", role: .cancel) { }
                    Button("OK", role: .cancel) { }
                } message: {
                    Text("Cái này chưa được tích hợp, hãy chờ đợi bản cập nhật mới")
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Cảnh báo", isPresented: $isShowingStorageAlert) {
            Button("Hủy", role: .cancel) { }
            Button("OK", role: .cancel) { }
        } message: {
            Text("Thiết bị này không đủ dung lượng để cài đặt ứng dụng này!")
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

    private var appSize: String {
        guard let size = app.fileSizeBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
    }

    private func metadataRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value).multilineTextAlignment(.trailing).textSelection(.enabled)
        }
    }
}
