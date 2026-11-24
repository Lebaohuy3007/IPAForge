import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @Environment(\.dismiss) private var dismiss
    @State private var appleID = ""
    @State private var password = ""
    @State private var verificationCode = ""
    @State private var isPasswordVisible = false
    @State private var showingAnisetteServers = false
    @State private var statusMessage = ""
    @State private var isSigningIn = false
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
                                    if result.state != .unchecked,
                                       !result.state.isUsable,
                                       !environment.anisetteServers.checkingIDs.contains(selectedID) {
                                        Text("Server chưa sẵn sàng (\(result.state.title)).")
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
                    if isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text(environment.authPhase == .waitingFor2FA
                                 ? "Waiting for verification…"
                                 : "Signing in…")
                        }
                    }

                    if environment.authPhase == .signedIn {
                        if let account = environment.activeAccount {
                            Label(account.appleID, systemImage: "person.crop.circle")
                            if !account.teams.isEmpty {
                                Picker("Developer Team", selection: Binding(
                                    get: { account.selectedTeamID ?? "" },
                                    set: { teamID in
                                        guard !teamID.isEmpty else { return }
                                        do {
                                            try environment.selectDeveloperTeam(id: teamID)
                                            statusMessage = ""
                                        } catch {
                                            statusMessage = error.localizedDescription
                                        }
                                    }
                                )) {
                                    Text("Select a team").tag("")
                                    ForEach(account.teams) { team in
                                        Text(team.name).tag(team.id)
                                    }
                                }
                            }
                        } else {
                            HStack(spacing: 8) {
                                ProgressView()
                                Text("Restoring Apple session…")
                            }
                        }
                        Button("Đăng xuất", role: .destructive) {
                            appleID = ""
                            password = ""
                            verificationCode = ""
                            isPasswordVisible = false
                            environment.signOut()
                            statusMessage = "Đã đăng xuất."
                        }
                    } else if environment.authPhase == .waitingFor2FA {
                        Text("Enter the six-digit verification code sent by Apple.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("Verification code", text: $verificationCode)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .disabled(!isSigningIn)
                        Button("Verify") { submitVerificationCode() }
                            .disabled(!isSigningIn)
                    } else if environment.authPhase == .authenticating && !isSigningIn {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Restoring Apple session…")
                        }
                    } else if isSigningIn {
                        EmptyView()
                    } else {
                        TextField("Apple ID / Email", text: $appleID)
                            .textContentType(.username)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .disabled(isSigningIn)
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
                            .disabled(isSigningIn)
                            Button {
                                isPasswordVisible.toggle()
                            } label: {
                                Image(systemName: isPasswordVisible ? "eye.slash" : "eye")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(isPasswordVisible ? "Hide password" : "Show password")
                        }
                        Button("Continue") { login() }
                    }
                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }

                Section {
                    LoginLogsView(logger: environment.logger)
                } header: {
                    HStack {
                        Text("Login Logs")
                        Spacer()
                        Button("Clear Logs") {
                            environment.logger.clearLogin()
                        }
                        .font(.caption)
                        .disabled(environment.logger.loginEntries.isEmpty)
                    }
                }
            }
            .navigationTitle("Apple Account")
            .onAppear {
                environment.anisetteServers.refreshAll()
            }
            .task(id: environment.anisetteServers.selectedServerID) {
                guard let selectedID = environment.anisetteServers.selectedServerID else { return }
                while !Task.isCancelled {
                    await environment.anisetteServers.refresh(serverID: selectedID)
                    do {
                        try await Task.sleep(nanoseconds: 1_000_000_000)
                    } catch {
                        return
                    }
                }
            }
            .sheet(isPresented: $showingAnisetteServers) {
                NavigationStack {
                    AnisetteServersView(store: environment.anisetteServers)
                }
            }
        }
    }

    private func login() {
        environment.logger.clearLogin()
        let submittedAppleID = appleID.trimmingCharacters(in: .whitespacesAndNewlines)
        let submittedPassword = password
        guard !submittedAppleID.isEmpty,
              !password.isEmpty else {
            statusMessage = "Vui lòng nhập Apple ID và mật khẩu, không để trống ô nào."
            environment.logger.logLogin(.warning, "Apple ID and password are required.")
            return
        }

        isSigningIn = true
        statusMessage = ""
        environment.logger.logLogin(.info, "Apple Account sign-in requested.")
        password = ""
        Task {
            defer {
                isSigningIn = false
                verificationCode = ""
            }
            do {
                try await environment.signIn(appleID: submittedAppleID, password: submittedPassword)
                dismiss()
            } catch {
                if error is CancellationError {
                    statusMessage = "Sign-in cancelled."
                } else {
                    statusMessage = LogSanitizer.sanitize(error.localizedDescription)
                    environment.logger.logLogin(.error, "Sign-in failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func submitVerificationCode() {
        do {
            try environment.submitVerificationCode(verificationCode)
            verificationCode = ""
            statusMessage = ""
        } catch {
            statusMessage = error.localizedDescription
        }
    }
}

private struct LoginLogsView: View {
    @ObservedObject var logger: LoggingService

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 6) {
                    if logger.loginEntries.isEmpty {
                        Text("Login events will appear here.")
                            .foregroundStyle(.secondary)
                            .id("empty-login-logs")
                    } else {
                        ForEach(logger.loginEntries) { entry in
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text(entry.formatted)
                                    .foregroundStyle(color(for: entry.level))
                                    .textSelection(.enabled)
                            }
                            .font(.system(.caption, design: .monospaced))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id(entry.id)
                        }
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
            }
            .frame(height: 150)
            .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 8))
            .onChange(of: logger.loginEntries.count) { _ in
                guard let lastEntry = logger.loginEntries.last else { return }
                withAnimation {
                    proxy.scrollTo(lastEntry.id, anchor: .bottom)
                }
            }
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .info: return .primary
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}
