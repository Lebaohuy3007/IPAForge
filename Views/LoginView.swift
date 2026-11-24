import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @AppStorage("anisetteServerURL") private var anisetteURL = AnisetteService.defaultURL
    @State private var appleID = ""
    @State private var password = ""
    @State private var anisetteStatus: AnisetteStatus = .unknown
    @State private var isTesting = false
    @State private var statusMessage = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Anisette Server") {
                    TextField("HTTPS server URL", text: $anisetteURL)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                    Text(anisetteStatus.label)
                        .foregroundStyle(anisetteStatus == .connected ? .green : .secondary)
                    HStack {
                        Button("Test Connection") { testServer() }
                            .disabled(isTesting)
                        Button("Save") {
                            UserDefaults.standard.set(anisetteURL, forKey: "anisetteServerURL")
                            statusMessage = "Server URL saved on this device."
                        }
                    }
                    if isTesting { ProgressView() }
                }

                Section("Apple Account") {
                    TextField("Apple ID / Email", text: $appleID)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                    Button("Login") { login() }
                        .disabled(appleID.isEmpty || password.isEmpty)
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
                    Text("Credentials are not sent or stored. Login is disabled until a supported Apple authentication implementation is available.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("AppStore IPA")
        }
    }

    private func testServer() {
        isTesting = true
        Task {
            anisetteStatus = await environment.anisette.testConnection(serverURL: anisetteURL)
            environment.logger.log(
                anisetteStatus == .connected ? .success : .warning,
                "Anisette HTTPS endpoint check: \(anisetteStatus.label)."
            )
            isTesting = false
        }
    }

    private func login() {
        password = ""
        statusMessage = AuthenticationError.unsupported.localizedDescription
        environment.logger.log(.error, "Apple Account sign-in is unavailable.")
    }
}
