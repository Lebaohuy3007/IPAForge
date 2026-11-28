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
    @State private var approvedServerIDs: Set<UUID> = []
    @State private var serverAwaitingApproval: AnisetteServer?
    @State private var serverToForget: AnisetteServer?

    init(store: AnisetteServerStore) {
        _store = ObservedObject(wrappedValue: store)
    }

    var body: some View {
        List {
            Section {
                ForEach(Array(store.servers.enumerated()), id: \.element.id) { index, server in
                    HStack(spacing: 8) {
                        Button {
                            select(server)
                        } label: {
                            AnisetteServerRow(
                                index: index,
                                server: server,
                                isSelected: store.selectedServerID == server.id,
                                isApproved: approvedServerIDs.contains(server.id),
                                isProvisioning: provisioningServerID == server.id
                            )
                        }
                        .buttonStyle(.plain)

                        if approvedServerIDs.contains(server.id) || !server.isDefault {
                            Menu {
                                if approvedServerIDs.contains(server.id) {
                                    Button(role: .destructive) {
                                        serverToForget = server
                                    } label: {
                                        Label("Forget Anisette identity", systemImage: "hand.raised.slash")
                                    }
                                }
                                if !server.isDefault {
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
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .foregroundStyle(.secondary)
                                    .frame(width: 32, height: 44)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel("Anisette server options")
                        }
                    }
                }
            } header: {
                Text("Chọn Anisette Server")
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
        .onAppear(perform: refreshApprovedServers)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
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
                    approvedServerIDs.remove(server.id)
                    serverToDelete = nil
                    errorMessage = nil
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        }
        .confirmationDialog(
            "Forget Anisette identity?",
            isPresented: Binding(
                get: { serverToForget != nil },
                set: { if !$0 { serverToForget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Forget identity", role: .destructive) {
                guard let server = serverToForget else { return }
                do {
                    try store.forgetAnisetteIdentity(serverID: server.id)
                    approvedServerIDs.remove(server.id)
                    serverToForget = nil
                    errorMessage = nil
                    environment.logger.log(.info, "Anisette identity approval revoked; stored identity cleared.")
                } catch {
                    errorMessage = error.localizedDescription
                }
            }
        } message: {
            Text("The saved Anisette identity and this server's approval will be deleted from this device.")
        }
        .alert("Anisette Server privacy", isPresented: Binding(
            get: { serverAwaitingApproval != nil },
            set: { if !$0 { serverAwaitingApproval = nil } }
        )) {
            Button("Hủy", role: .cancel) {
                serverAwaitingApproval = nil
            }
            Button("Continue", role: .destructive) {
                approveAndSelectServer()
            }
        } message: {
            if let server = serverAwaitingApproval {
                Text("The selected server will receive a persistent Anisette identifier and adi_pb provisioning data over HTTPS. During provisioning, the app also sends some Apple provisioning exchange values through this server; its operator can read and retain the values it receives. Your Apple ID password and 2FA code are not sent to the Anisette Server.")
                Text(verbatim: server.url).textSelection(.enabled)
            }
        }
    }

    @MainActor
    private func select(_ server: AnisetteServer) {
        do {
            guard try store.hasAnisetteApproval(serverID: server.id) else {
                serverAwaitingApproval = server
                return
            }
            approvedServerIDs.insert(server.id)
            beginProvisioning(using: server)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func approveAndSelectServer() {
        guard let server = serverAwaitingApproval else { return }
        do {
            try store.approveAnisetteUse(serverID: server.id)
            approvedServerIDs.insert(server.id)
            serverAwaitingApproval = nil
            beginProvisioning(using: server)
        } catch {
            serverAwaitingApproval = nil
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func beginProvisioning(using server: AnisetteServer) {
        do {
            try store.select(serverID: server.id)
            errorMessage = nil
            provisioningTask?.cancel()

            let requestID = UUID()
            provisioningRequestID = requestID
            provisioningServerID = server.id
            let host = URL(string: server.url)?.host ?? "Anisette Server"
            environment.logger.log(.info, "Anisette v3 provisioning started | Server: \(host).", correlationID: requestID)
            let startedAt = Date()
            provisioningTask = Task { @MainActor in
                defer {
                    if provisioningRequestID == requestID {
                        provisioningRequestID = nil
                        provisioningServerID = nil
                        provisioningTask = nil
                    }
                }
                do {
                    _ = try await environment.anisette.fetchAnisetteV3(
                        serverURL: server.url,
                        correlationID: requestID
                    )
                    guard provisioningRequestID == requestID else { return }
                    let duration = Int(Date().timeIntervalSince(startedAt) * 1_000)
                    environment.logger.log(.success, "Anisette v3 provisioning completed | Server: \(host) | Duration: \(duration) ms.", correlationID: requestID)
                    await environment.restoreSavedSessionAfterAnisetteApproval()
                } catch is CancellationError {
                    guard provisioningRequestID == requestID else { return }
                    environment.logger.log(.warning, "Anisette v3 provisioning cancelled | Server: \(host).", correlationID: requestID)
                } catch {
                    guard provisioningRequestID == requestID else { return }
                    errorMessage = error.localizedDescription
                    environment.logger.log(
                        .error,
                        "Anisette v3 provisioning failed | Server: \(host) | Reason: \(LogSanitizer.sanitize(error.localizedDescription)).",
                        correlationID: requestID
                    )
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func refreshApprovedServers() {
        approvedServerIDs = Set(store.servers.compactMap { server in
            (try? store.hasAnisetteApproval(serverID: server.id)) == true ? server.id : nil
        })
    }
}

private struct AnisetteServerRow: View {
    let index: Int
    let server: AnisetteServer
    let isSelected: Bool
    let isApproved: Bool
    let isProvisioning: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(index + 1) \(server.name)")
                        .font(.headline)
                    Spacer()
                    if isProvisioning {
                        ProgressView()
                            .controlSize(.small)
                    } else if isSelected {
                        Image(systemName: "checkmark")
                            .foregroundStyle(.green)
                    }
                }
                Text(verbatim: server.url)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(isApproved ? "Anisette use approved" : "Approval required before use")
                    .font(.caption2)
                    .foregroundStyle(isApproved ? .secondary : .orange)
            }
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
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

enum AnisetteServerURLInput {
    static func suffix(from value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("https://") {
            return String(trimmed.dropFirst("https://".count))
        }
        if trimmed.lowercased().hasPrefix("http://") {
            return String(trimmed.dropFirst("http://".count))
        }
        return trimmed
    }

    static func fullURL(from suffix: String) -> String {
        "https://\(self.suffix(from: suffix))"
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
    @State private var showUnreachableConfirmation = false

    init(server: AnisetteServer? = nil) {
        self.server = server
        _name = State(initialValue: server?.name ?? "")
        _url = State(initialValue: AnisetteServerURLInput.suffix(from: server?.url ?? ""))
    }

    var body: some View {
        Form {
            Section("Thông tin Server") {
                TextField("Tên nguồn (không bắt buộc)", text: $name)
                    .textInputAutocapitalization(.words)
                HStack(spacing: 0) {
                    Text("https://")
                        .foregroundStyle(.secondary)
                    TextField("example.com", text: Binding(
                        get: { url },
                        set: { url = AnisetteServerURLInput.suffix(from: $0) }
                    ))
                    .textInputAutocapitalization(.never)
                    .keyboardType(.URL)
                    .autocorrectionDisabled()
                }
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
        .alert("Thông báo", isPresented: $showUnreachableConfirmation) {
            Button("Hủy", role: .cancel) {}
            Button("OK") {
                saveNewServer()
            }
        } message: {
            Text("URL này có thể không hợp lệ. Bạn có chắc muốn thêm vào danh sách không?")
        }
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
                        url: AnisetteServerURLInput.fullURL(from: url)
                    )
                } else {
                    let normalizedURL = AnisetteServerURLInput.fullURL(from: url)
                    let result = await environment.anisette.testConnection(serverURL: normalizedURL)
                    guard result.state != .noResponse && result.state != .invalidURL else {
                        showUnreachableConfirmation = true
                        isSaving = false
                        return
                    }
                    _ = try await environment.anisetteServers.add(
                        name: name,
                        url: normalizedURL
                    )
                }
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }

    private func saveNewServer() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                _ = try await environment.anisetteServers.add(
                    name: name,
                    url: AnisetteServerURLInput.fullURL(from: url)
                )
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
