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
    @State private var checkingAllServers = false

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
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Đóng") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button(checkingAllServers ? "Đang kiểm tra…" : "Kiểm tra") {
                    guard !checkingAllServers else { return }
                    checkingAllServers = true
                    store.refreshAll(force: true)
                    Task { @MainActor in
                        while !store.checkingIDs.isEmpty {
                            try? await Task.sleep(for: .milliseconds(100))
                        }
                        checkingAllServers = false
                    }
                }
                .disabled(checkingAllServers)
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
    @ObservedObject var store: AnisetteServerStore

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("#\(index + 1) \(server.name)")
                        .font(.headline)
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
            ProgressView()
                .controlSize(.small)
                .foregroundStyle(.secondary)
        } else if let result = store.probeResults[serverID] {
            if result.state != .unchecked, let milliseconds = result.durationMilliseconds {
                Text(result.state == .noResponse || result.state == .invalidURL
                     ? "Không kết nối được · \(milliseconds) ms"
                     : "\(milliseconds) ms")
                    .font(.caption)
                    .foregroundStyle(result.state == .noResponse || result.state == .invalidURL ? .red : .secondary)
            }
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
            Button("Cancel", role: .cancel) {}
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
