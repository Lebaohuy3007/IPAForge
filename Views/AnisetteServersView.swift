import SwiftUI

struct AnisetteServersView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var editorRoute: ServerEditorRoute?
    @State private var serverToDelete: AnisetteServer?
    @State private var errorMessage: String?
    @State private var v3ResultMessage: String?
    @State private var isFetchingV3 = false
    @State private var showsV3ProvisioningConfirmation = false

    var body: some View {
        List {
            if environment.anisetteServers.hasFinishedInitialChecks &&
                !environment.anisetteServers.hasUsableServer {
                Section {
                    Label(
                        "Hiện tại không có Anisette Server khả dụng. Hãy kiểm tra kết nối hoặc thêm nguồn khác.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Chọn Anisette Server") {
                ForEach(Array(environment.anisetteServers.servers.enumerated()), id: \.element.id) { index, server in
                    HStack(spacing: 8) {
                        Button {
                            do {
                                try environment.anisetteServers.select(serverID: server.id)
                                errorMessage = nil
                            } catch {
                                errorMessage = error.localizedDescription
                            }
                        } label: {
                            AnisetteServerRow(
                                index: index,
                                server: server,
                                isSelected: environment.anisetteServers.selectedServerID == server.id,
                                store: environment.anisetteServers
                            )
                        }
                        .buttonStyle(.plain)

                        if !server.isDefault {
                            Menu {
                                Button {
                                    editorRoute = .edit(server)
                                } label: {
                                    Label("Sửa nguồn", systemImage: "pencil")
                                }
                                Button(role: .destructive) {
                                    serverToDelete = server
                                } label: {
                                    Label("Xóa nguồn", systemImage: "trash")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Tùy chọn \(server.name)")
                        }
                    }
                }
            }

            Section {
                Button {
                    editorRoute = .add
                } label: {
                    Label("Thêm nguồn mới", systemImage: "plus")
                }
            }

            Section("Anisette v3") {
                Text("Máy chủ đã chọn sẽ nhận dữ liệu provisioning Anisette. Apple ID, mật khẩu và mã xác minh không được gửi.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button {
                    showsV3ProvisioningConfirmation = true
                } label: {
                    if isFetchingV3 {
                        ProgressView("Đang tạo dữ liệu Anisette v3…")
                    } else {
                        Label("Tạo dữ liệu Anisette v3", systemImage: "key.horizontal")
                    }
                }
                .disabled(isFetchingV3 || !selectedServerSupportsV3)

                if let v3ResultMessage {
                    Text(v3ResultMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

        }
        .navigationTitle("Anisette Server")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Kiểm tra") {
                    environment.anisetteServers.refreshAll(force: true)
                }
            }
        }
        .onAppear {
            environment.anisetteServers.refreshAll()
        }
        .confirmationDialog(
            "Provisioning Anisette v3",
            isPresented: $showsV3ProvisioningConfirmation,
            titleVisibility: .visible
        ) {
            Button("Tiếp tục") {
                Task { await fetchV3Data() }
            }
            Button("Hủy", role: .cancel) {}
        } message: {
            Text("Máy chủ Anisette đã chọn sẽ nhận identifier và dữ liệu provisioning Apple cần để tạo adi.pb. Không gửi thông tin đăng nhập Apple.")
        }
        .sheet(item: $editorRoute) { route in
            NavigationStack {
                switch route {
                case .add:
                    AnisetteServerEditorView()
                case .edit(let server):
                    AnisetteServerEditorView(server: server)
                }
            }
        }
        .confirmationDialog(
            "Xóa nguồn Anisette?",
            isPresented: Binding(
                get: { serverToDelete != nil },
                set: { if !$0 { serverToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Xóa nguồn", role: .destructive) {
                guard let server = serverToDelete else { return }
                do {
                    try environment.anisetteServers.delete(serverID: server.id)
                    serverToDelete = nil
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    private var selectedServerSupportsV3: Bool {
        guard let id = environment.anisetteServers.selectedServerID else { return false }
        return environment.anisetteServers.probeResults[id]?.state == .validV3
    }

    @MainActor
    private func fetchV3Data() async {
        guard let server = environment.anisetteServers.selectedServer else { return }
        isFetchingV3 = true
        defer { isFetchingV3 = false }
        do {
            _ = try await environment.anisette.fetchAnisetteV3(serverURL: server.url)
            v3ResultMessage = "Anisette v3 đã sẵn sàng cho máy chủ \(server.name)."
        } catch {
            v3ResultMessage = error.localizedDescription
        }
    }
}

private struct AnisetteServerRow: View {
    let index: Int
    let server: AnisetteServer
    let isSelected: Bool
    @ObservedObject var store: AnisetteServerStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(index + 1) \(server.name)")
                        .font(.headline)
                    if server.isDefault {
                        Text("Mặc định")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
                Text(server.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                AnisetteProbeStatusView(serverID: server.id, store: store)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

struct AnisetteProbeStatusView: View {
    let serverID: UUID
    @ObservedObject var store: AnisetteServerStore

    var body: some View {
        if store.checkingIDs.contains(serverID) {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Đang kiểm tra…").font(.caption)
            }
            .foregroundStyle(.secondary)
        } else if let result = store.probeResults[serverID] {
            HStack(spacing: 4) {
                Text(result.state.title)
                if let milliseconds = result.durationMilliseconds {
                    Text("· \(milliseconds) ms")
                }
            }
            .font(.caption)
            .foregroundStyle(result.state.isUsable ? Color.green : Color.secondary)
        } else {
            Text(AnisetteProbeState.unchecked.title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private enum ServerEditorRoute: Identifiable {
    case add
    case edit(AnisetteServer)

    var id: String {
        switch self {
        case .add:
            return "add"
        case .edit(let server):
            return "edit-\(server.id)"
        }
    }
}

private struct AnisetteServerEditorView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    let server: AnisetteServer?
    @State private var name: String
    @State private var url: String
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(server: AnisetteServer? = nil) {
        self.server = server
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: server?.url ?? "")
    }

    var body: some View {
        Form {
            Section("Thông tin Server") {
                TextField("Tên nguồn (không bắt buộc)", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("https://example.com", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }
            if isSaving {
                Section { ProgressView("Đang kiểm tra server…") }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
        }
        .navigationTitle(server == nil ? "Thêm Anisette Server" : "Sửa Anisette Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button("Hủy") { dismiss() }
                    .disabled(isSaving)
            }
            ToolbarItem(placement: .navigationBarTrailing) {
                Button(server == nil ? "Thêm" : "Lưu") { save() }
                    .disabled(isSaving || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                if let server {
                    try await environment.anisetteServers.update(
                        serverID: server.id,
                        name: name,
                        url: url
                    )
                } else {
                    _ = try await environment.anisetteServers.add(name: name, url: url)
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
