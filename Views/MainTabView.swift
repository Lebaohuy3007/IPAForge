import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            AppStoreSearchView()
                .tabItem { Label("App Store", systemImage: "bag") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var destination: ProfileDestination?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "person.crop.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.tint)
                        Text(environment.authPhase == .signedIn
                             ? (environment.activeAccount?.appleID ?? "Apple Account")
                             : "Your Profile")
                            .font(.title3.bold())
                        Text(profileStatus)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if environment.authPhase == .signedOut {
                            Button("Apple Account Sign In") {
                                destination = .login
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    private var profileStatus: String {
                        switch environment.authPhase {
                        case .signedOut:
                            return "Sign in with your Apple Account."
                        case .waitingFor2FA:
                            return "Waiting for Apple two-factor verification."
                        case .authenticating:
                            return "Authenticating or restoring your Apple session…"
                        case .signedIn:
                            return "Signed in"
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section("Your Library") {
                    profileRow("Downloads", symbol: "arrow.down.circle", destination: .downloads)
                }

                Section("Account") {
                    profileRow("Saved Accounts", symbol: "person.2", destination: .savedAccounts)
                    profileRow("Anisette Server", symbol: "server.rack", destination: .anisette)
                }

                Section("Support") {
                    profileRow("Activity Log", symbol: "text.alignleft", destination: .logs)
                }

                Section {
                    LabeledContent("Version", value: IPAForgeVersion.displayValue())
                }
            }
            .navigationTitle("Profile")
            .sheet(item: $destination) { destination in
                switch destination {
                case .login:
                    LoginView()
                case .downloads:
                    DownloadManagerView()
                case .savedAccounts:
                    SavedAccountsView()
                case .anisette:
                    AnisetteServersView()
                case .logs:
                    LogViewerView()
                }
            }
        }
    }

    private func profileRow(
        _ title: String,
        symbol: String,
        destination: ProfileDestination
    ) -> some View {
        Button {
            self.destination = destination
        } label: {
            Label(title, systemImage: symbol)
        }
        .foregroundStyle(.primary)
    }
}

private enum ProfileDestination: String, Identifiable {
    case login
    case downloads
    case savedAccounts
    case anisette
    case logs

    var id: String { rawValue }
}
