import SwiftUI

struct AnisetteServersView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var showingAdd = false

    var body: some View {
        List {
            if environment.anisetteServers.hasFinishedInitialChecks &&
                !environment.anisetteServers.hasUsableServer {
                Section {
                    Label(
                        "Hiện tại không có Anisette Server khả dụng. Hãy kiểm tra kết nối, thử lại hoặc thêm server khác.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                    Button("Thử lại tất cả") {
                        environment.anisetteServers.refreshAll(force: true)
                    }
                }
            }

            Section("Anisette Server · Anisette v1") {
                ForEach(Array(environment.anisetteServers.servers.enumerated()), id: \.element.id) { index, server in
                    NavigationLink {
                        AnisetteServerDetailView(server: server)
                    } label: {
                        AnisetteServerRow(index: index, server: server)
                    }
                }
            }

            Section {
                Button {
                    showingAdd = true
                } label: {
                    Label("Thêm nguồn mới", systemImage: "plus")
                }
            }

            Section {
                Text("Chỉ phản hồi JSON có X-Apple-I-MD và X-Apple-I-MD-M không rỗng mới được đánh dấu Anisette v1 hợp lệ. Endpoint v3/provisioning chưa được tích hợp.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Anisette Server")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Kiểm tra lại") {
                    environment.anisetteServers.refreshAll(force: true)
                }
            }
        }
        .onAppear {
            environment.anisetteServers.refreshAll()
        }
        .sheet(isPresented: $showingAdd) {
            NavigationStack {
                AnisetteServerEditorView()
            }
        }
    }
}

struct AnisetteServerPickerView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var pendingServerID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section("Chọn Anisette Server") {
                ForEach(Array(environment.anisetteServers.servers.enumerated()), id: \.element.id) { index, server in
                    Button {
                        pendingServerID = server.id
                    } label: {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: pendingServerID == server.id ? "largecircle.fill.circle" : "circle")
                                .foregroundStyle(
                                    pendingServerID == server.id ? Color.accentColor : Color.secondary
                                )
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text("#\(index + 1) \(server.name)")
                                        .font(.headline)
                                    Spacer()
                                    if environment.anisetteServers.selectedServerID == server.id {
                                        Image(systemName: "checkmark").foregroundStyle(.green)
                                    }
                                }
                                Text(server.url).font(.caption).foregroundStyle(.secondary)
                                AnisetteProbeStatusView(
                                    serverID: server.id,
                                    store: environment.anisetteServers
                                )
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Button("Chọn máy chủ") {
                    guard let pendingServerID else { return }
                    do {
                        try environment.anisetteServers.select(serverID: pendingServerID)
                        dismiss()
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                .disabled(pendingServerID == nil)
            }
            Section {
                Text("Máy chủ phải trả về JSON Anisette v1 hợp lệ mới có thể được chọn. Việc kiểm tra không đăng nhập Apple ID.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Anisette Server")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Đóng") { dismiss() }
            }
        }
        .onAppear {
            pendingServerID = environment.anisetteServers.selectedServerID
            environment.anisetteServers.refreshAll()
        }
    }
}

private struct AnisetteServerRow: View {
    @EnvironmentObject private var environment: AppEnvironment
    let index: Int
    let server: AnisetteServer

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(index + 1) \(server.name)").font(.headline)
                    if server.isDefault {
                        Text("Mặc định")
                            .font(.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.secondary.opacity(0.15), in: Capsule())
                    }
                    Spacer()
                    if environment.anisetteServers.selectedServerID == server.id {
                        Image(systemName: "checkmark").foregroundStyle(.green)
                    }
                }
                Text(server.url).font(.caption).foregroundStyle(.secondary)
                AnisetteProbeStatusView(serverID: server.id, store: environment.anisetteServers)
            }
        }
        .padding(.vertical, 3)
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

private struct AnisetteServerDetailView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var server: AnisetteServer
    @State private var showingEdit = false
    @State private var showingDeleteConfirmation = false
    @State private var errorMessage: String?

    init(server: AnisetteServer) {
        _server = State(initialValue: server)
    }

    var body: some View {
        Form {
            Section("Server") {
                LabeledContent("Tên", value: server.name)
                LabeledContent("URL", value: server.url)
                LabeledContent(
                    "Trạng thái",
                    value: environment.anisetteServers.checkingIDs.contains(server.id)
                        ? "Đang kiểm tra…"
                        : (environment.anisetteServers.probeResults[server.id]?.state.title ?? "Chưa kiểm tra")
                )
                if let milliseconds = environment.anisetteServers.probeResults[server.id]?.durationMilliseconds {
                    LabeledContent("Thời gian phản hồi", value: "\(milliseconds) ms")
                }
            }
            Section {
                Button("Kiểm tra lại") {
                    Task { await environment.anisetteServers.refresh(serverID: server.id) }
                }
                if environment.anisetteServers.selectedServerID == server.id {
                    Label("Đang được chọn", systemImage: "checkmark")
                        .foregroundStyle(.green)
                } else {
                    Button("Chọn máy chủ") {
                        do {
                            try environment.anisetteServers.select(serverID: server.id)
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                    .disabled(environment.anisetteServers.probeResults[server.id]?.state.isUsable != true)
                }
            }
            if !server.isDefault {
                Section {
                    Button("Sửa nguồn") { showingEdit = true }
                    Button("Xóa nguồn", role: .destructive) {
                        showingDeleteConfirmation = true
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red) }
            }
            Section {
                Text("Kiểm tra dùng GET endpoint gốc của giao thức Anisette v1. Không gửi Apple ID, mật khẩu, mã 2FA, token hoặc identity Anisette.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(server.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if environment.anisetteServers.probeResults[server.id]?.state == .unchecked {
                Task { await environment.anisetteServers.refresh(serverID: server.id) }
            }
        }
        .onChange(of: environment.anisetteServers.servers) { updatedServers in
            guard let updated = updatedServers.first(where: { $0.id == server.id }) else {
                dismiss()
                return
            }
            server = updated
        }
        .sheet(isPresented: $showingEdit) {
            NavigationStack {
                AnisetteServerEditorView(server: server)
            }
        }
        .confirmationDialog(
            "Xóa \(server.name)?",
            isPresented: $showingDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Xóa nguồn", role: .destructive) {
                do {
                    try environment.anisetteServers.delete(serverID: server.id)
                    dismiss()
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("Nguồn đã chọn sẽ bị bỏ chọn. IPAForge không tự chuyển sang máy chủ khác.")
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
            Section {
                Text("Thêm địa chỉ Anisette Server để IPAForge có thể kiểm tra, lưu và sử dụng khi đăng nhập Apple ID.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Section("Thông tin Server") {
                TextField("Tên nguồn (không bắt buộc)", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("https://example.com", text: $url)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
            }
            if isSaving { Section { ProgressView("Đang kiểm tra server…") } }
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
