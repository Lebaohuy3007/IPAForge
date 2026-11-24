import SwiftUI

struct AnisetteServersView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store: AnisetteServerStore
    @State private var editorRoute: ServerEditorRoute?
    @State private var serverToDelete: AnisetteServer?
    @State private var errorMessage: String?
    @State private var provisioningServerID: UUID?
    @State private var provisioningRequestID: UUID?
    @State private var provisioningTask: Task<Void, Never>?

    init(store: AnisetteServerStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        List {
            if store.hasFinishedInitialChecks && !store.hasUsableServer {
                Section {
                    Label(
                        "Hiện tại không có Anisette Server khả dụng. Hãy kiểm tra kết nối hoặc thêm nguồn khác.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .foregroundStyle(.orange)
                }
            }

            Section("Chọn Anisette Server") {
                ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                    HStack(spacing: 8) {
                        Button {
                            select(server)
                        } label: {
                            AnisetteServerRow(
                                index: index,
                                server: server,
                                isSelected: store.selectedServerID == server.id,
                                isProvisioning: provisioningServerID == server.id,
                                store: store
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
            } footer: {
                Text("Khi chọn server, ứng dụng tự tạo dữ liệu Anisette v3. Server nhận identifier và dữ liệu provisioning Apple; Apple ID, mật khẩu và mã xác minh không được gửi.")
            }

            Section {
                Button {
                    editorRoute = .add
                } label: {
                    Label("Thêm nguồn mới", systemImage: "plus")
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
                    store.refreshAll(force: true)
                }
            }
        }
        .onAppear {
            store.refreshAll()
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
                    try store.delete(serverID: server.id)
                    serverToDelete = nil
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
    }

    @MainActor
    private func select(_ server: AnisetteServer) {
        do {
            try store.select(serverID: server.id)
            errorMessage = nil
            provisioningTask?.cancel()

            let requestID = UUID()
            provisioningRequestID = requestID
            provisioningServerID = server.id
            provisioningTask = Task { @MainActor in
                defer {
                    if provisioningRequestID == requestID {
                        provisioningRequestID = nil
                        provisioningServerID = nil
                        provisioningTask = nil
                    }
                }
                do {
                    _ = try await environment.anisette.fetchAnisetteV3(serverURL: server.url)
                } catch is CancellationError {
                    return
                } catch {
                    guard provisioningRequestID == requestID else { return }
                    errorMessage = error.localizedDescription
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct AnisetteServerRow: View {
    let index: Int
    let server: AnisetteServer
    let isSelected: Bool
    let isProvisioning: Bool
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
                if isProvisioning {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Đang tạo dữ liệu Anisette v3…")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                }
                if !isProvisioning {
                    AnisetteProbeStatusView(serverID: server.id, store: store)
                }
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
            ProgressView()
                .controlSize(.small)
                .foregroundStyle(.secondary)
        } else if let result = store.probeResults[serverID] {
            if let milliseconds = result.durationMilliseconds {
                Text("\(milliseconds) ms")
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            } else {
                Text(result.state.title)
                    .font(.caption)
                    .foregroundStyle(Color.secondary)
            }
        } else {
            Text("— ms")
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
                Section {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Đang kiểm tra server…")
                    }
                }
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
