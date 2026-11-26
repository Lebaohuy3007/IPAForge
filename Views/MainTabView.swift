import SwiftUI
import UIKit

struct MainTabView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        TabView {
            AppStoreSearchView()
                .tabItem { Label("App Store", systemImage: "bag") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
            DownloadManagerView(downloads: environment.downloads)
                .tabItem { Label("iPA Downloader", systemImage: "arrow.down.circle") }
        }
        .environmentObject(environment.deviceProfiles)
    }
}

private struct ProfileView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var destination: ProfileDestination?

    var body: some View {
        NavigationStack {
            List {
                Section {
                    profileAccountSection
                }

                Section("Your Library") {
                    profileRow("Downloads", symbol: "arrow.down.circle", destination: .downloads)
                }

                Section("Compatibility") {
                    profileRow("Device Profile (iOS 27+)", symbol: "iphone.gen3", destination: .deviceProfile)
                }

                Section("Account") {
                    profileRow("Anisette Server", symbol: "server.rack", destination: .anisette)
                }

                Section("Settings") {
                    Picker("Language", selection: Binding(
                        get: { environment.languagePreference ?? environment.appLanguage },
                        set: { environment.languagePreference = $0 }
                    )) {
                        ForEach(AppLanguage.allCases) { language in
                            Text(LocalizedStringKey(language.titleKey)).tag(language)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section("Support") {
                    profileRow("Activity Log", symbol: "text.alignleft", destination: .logs)
                }

                Section("Project") {
                    Link(destination: URL(string: "https://github.com/Lebaohuy3007")!) {
                        Label("GitHub Repository", systemImage: "heart.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .foregroundStyle(.primary)
                } footer: {
                    Text("Version \(IPAForgeVersion.displayValue()) • iOS \(UIDevice.current.systemVersion)")
                        .frame(maxWidth: .infinity, alignment: .center)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Profile")
            .sheet(item: $destination) { destination in
                switch destination {
                case .login:
                    LoginView()
                case .downloads:
                    DownloadManagerView(downloads: environment.downloads)
                case .anisette:
                    AnisetteServersView(store: environment.anisetteServers)
                case .logs:
                    LogViewerView()
                case .deviceProfile:
                    DeviceProfileView()
                }
            }
        }
    }

    @ViewBuilder
    private var profileAccountSection: some View {
        if environment.authPhase == .authenticating {
            HStack(spacing: 10) {
                ProgressView()
                Text("Đang khôi phục phiên đăng nhập…")
                    .foregroundStyle(.secondary)
            }
        } else if environment.authPhase == .signedIn,
                  let account = environment.activeAccount {
            HStack(spacing: 12) {
                profileImage
                VStack(alignment: .leading, spacing: 5) {
                    Text(account.appleID)
                        .font(.headline)
                        .textSelection(.enabled)
                    Label("Signed in", systemImage: "checkmark.circle.fill")
                        .font(.subheadline)
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)

            let regionCode = (account.storeCountry ?? environment.country).uppercased()
            LabeledContent(
                "Region",
                value: "\(regionCode) (\(Locale.current.localizedString(forRegionCode: regionCode) ?? regionCode))"
            )

            if account.teams.count > 1 {
                Picker("Developer Team", selection: Binding(
                    get: { account.selectedTeamID ?? "" },
                    set: { teamID in
                        guard !teamID.isEmpty else { return }
                        do {
                            try environment.selectDeveloperTeam(id: teamID)
                        } catch {
                            environment.authMessage = error.localizedDescription
                        }
                    }
                )) {
                    Text("Select a team").tag("")
                    ForEach(account.teams) { team in
                        Text(team.name).tag(team.id)
                    }
                }
                .pickerStyle(.menu)
            }

            if !environment.authMessage.isEmpty {
                Text(environment.authMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button(role: .destructive) {
                environment.signOut()
            } label: {
                Label("Đăng xuất", systemImage: "rectangle.portrait.and.arrow.right")
            }
        } else {
            Button {
                destination = .login
            } label: {
                HStack(spacing: 12) {
                    profileImage
                    Text("Đăng nhập bằng Tài khoản Apple")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if !environment.authMessage.isEmpty {
                Text(environment.authMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }

    private var profileImage: some View {
        Image(systemName: "person.crop.circle.fill")
            .font(.system(size: 48))
            .foregroundStyle(.tint)
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
    case anisette
    case logs
    case deviceProfile

    var id: String { rawValue }
}
