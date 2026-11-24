import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var appleID = ""
    @State private var password = ""
    @State private var isPasswordVisible = false
    @State private var showingAnisetteServers = false
    @State private var statusMessage = ""
    @FocusState private var passwordFieldIsFocused: Bool

    var body: some View {
        NavigationStack {
            Form {
                Section("Anisette Server") {
                    Button {
                        showingAnisetteServers = true
                    } label: {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(environment.anisetteServers.selectedServer?.name ?? "Chưa chọn")
                                    .font(.headline)
                                if let selectedServer = environment.anisetteServers.selectedServer {
                                    Text(selectedServer.url)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                if let selectedID = environment.anisetteServers.selectedServerID,
                                   let result = environment.anisetteServers.probeResults[selectedID] {
                                    AnisetteProbeStatusView(
                                        serverID: selectedID,
                                        store: environment.anisetteServers
                                    )
                                    if !result.state.isUsable {
                                        Text("Server hiện không sẵn sàng.")
                                            .font(.caption)
                                            .foregroundStyle(.orange)
                                    }
                                }
                            }
                            Spacer(minLength: 8)
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    if environment.anisetteServers.hasFinishedInitialChecks &&
                        !environment.anisetteServers.hasUsableServer {
                        Label(
                            "Không có Anisette Server khả dụng. Hãy thử lại hoặc thêm nguồn.",
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
                    if environment.authPhase == .signedIn {
                        Label(appleID, systemImage: "person.crop.circle")
                        Button("Đăng xuất", role: .destructive) {
                            appleID = ""
                            password = ""
                            isPasswordVisible = false
                            environment.signOut()
                            statusMessage = "Đã đăng xuất."
                        }
                    } else {
                        TextField("Apple ID / Email", text: $appleID)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                        HStack {
                            Group {
                                if isPasswordVisible {
                                    TextField("Password", text: $password)
                                        .focused($passwordFieldIsFocused)
                                        .submitLabel(.done)
                                        .onSubmit { passwordFieldIsFocused = false }
                                } else {
                                    SecureField("Password", text: $password)
                                        .focused($passwordFieldIsFocused)
                                        .submitLabel(.done)
                                        .onSubmit { passwordFieldIsFocused = false }
                                }
                            }
                            .textContentType(.password)
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                        }
                        Button("Login") { login() }
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
            .navigationTitle("Apple Account")
            .onAppear {
                environment.anisetteServers.refreshAll()
            }
            .sheet(isPresented: $showingAnisetteServers) {
                NavigationStack {
                    AnisetteServersView()
                }
            }
        }
    }

    private func login() {
        guard !appleID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !password.isEmpty else {
            statusMessage = "Vui lòng nhập Apple ID và mật khẩu, không để trống ô nào."
            return
        }
        statusMessage = AuthenticationError.unsupported.localizedDescription
        environment.logger.log(.error, "Apple Account sign-in is unavailable.")
    }
}
