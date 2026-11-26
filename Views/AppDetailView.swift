import SwiftUI

struct AppDetailView: View {
    @State private var isShowingOldVersions = false
    @EnvironmentObject private var deviceProfiles: DeviceProfileStore
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

                VStack(alignment: .leading, spacing: 10) {
                    Text("Compatibility")
                        .font(.title3.bold())
                    CompatibilityReportView(report: CompatibilityChecker().evaluate(
                        requirements: .fromCatalog(app),
                        profile: deviceProfiles.selectedProfile
                    ))
                }

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

                VStack(alignment: .leading, spacing: 8) {
                    Button {} label: {
                        Label("Tải IPA (chưa khả dụng)", systemImage: "arrow.down.to.line")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(true)

                    Text("Đăng nhập App Store và quyền tải ứng dụng chưa được triển khai, nên IPAForge chưa thể tải IPA. Không có dữ liệu tải giả.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
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
