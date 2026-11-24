import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var appleID = ""
    @State private var password = ""
    @State private var serverSheet: ServerSheet?
    @State private var statusMessage = ""

    private enum ServerSheet: String, Identifiable {
        case picker
        case manager

        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Anisette Server") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(environment.anisetteServers.selectedServer?.name ?? "Chưa chọn")
                                .font(.headline)
                            Text(environment.anisetteServers.selectedServer?.url ?? "Chọn server đã xác thực Anisette")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if let selectedID = environment.anisetteServers.selectedServerID,
                               let result = environment.anisetteServers.probeResults[selectedID] {
                                AnisetteProbeStatusView(serverID: selectedID, store: environment.anisetteServers)
                                if !result.state.isUsable {
                                    Text("Server hiện không sẵn sàng; không tự chuyển nguồn.")
                                        .font(.caption)
                                        .foregroundStyle(.orange)
                                }
                            }
                        }
                        Spacer()
                        Button("Chọn") { serverSheet = .picker }
                            .disabled(environment.anisetteServers.servers.isEmpty)
                    }
                    Button("Quản lý Anisette Server") { serverSheet = .manager }
                    if environment.anisetteServers.hasFinishedInitialChecks &&
                        !environment.anisetteServers.hasUsableServer {
                        Label(
                            "Không có Anisette nào được dùng. Hãy thử lại hoặc quản lý server.",
                            systemImage: "exclamationmark.triangle"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                        Button("Thử lại") {
                            environment.anisetteServers.refreshAll(force: true)
                        }
                    }
                }

                Section("Apple Account") {
                    TextField("Apple ID / Email", text: $appleID)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    Button("Login") { login() }
                        .disabled(appleID.isEmpty || password.isEmpty || !hasReadyAnisette)
                    Button("Cancel Login", role: .destructive) {
                        password = ""
                        environment.cancelLogin()
                        statusMessage = "Login cancelled."
                    }
                }

                Section("Status") {
                    Text(statusMessage.isEmpty
                         ? "Apple Account authentication is currently unavailable."
                         : statusMessage)
                        .foregroundStyle(.secondary)
                    Text("IPAForge không gửi Apple ID, mật khẩu hoặc mã 2FA đến Anisette Server. Apple SRP Authentication chưa được tích hợp trong phiên bản này.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AppStore IPA")
            .onAppear {
                environment.anisetteServers.refreshAll()
            }
            .sheet(item: $serverSheet) { sheet in
                NavigationStack {
                    if sheet == .picker {
                        AnisetteServerPickerView()
                    } else {
                        AnisetteServersView()
                    }
                }
            }
        }
    }

    private var hasReadyAnisette: Bool {
        guard let selectedID = environment.anisetteServers.selectedServerID,
              !environment.anisetteServers.checkingIDs.contains(selectedID) else {
            return false
        }
        return environment.anisetteServers.probeResults[selectedID]?.state.isUsable == true
    }

    private func login() {
        password = ""
        statusMessage = AuthenticationError.unsupported.localizedDescription
        environment.logger.log(.error, "Apple Account sign-in is unavailable.")
    }
}
