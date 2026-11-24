import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            AppStoreDemoView()
                .tabItem { Label("App Store", systemImage: "bag") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
    }
}

private struct AppStoreDemoView: View {
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                        Text("DEMO · Chưa kết nối App Store")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.blue)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(.blue.opacity(0.1), in: Capsule())

                    HStack {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        Text("Games, apps, and more")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(12)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 12) {
                        Text("Today").font(.largeTitle.bold())
                        Text("Discover something great")
                            .font(.title3.weight(.medium))
                            .foregroundStyle(.secondary)
                        FeaturedDemoCard()
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        sectionHeading("Apps to explore", subtitle: "A preview of the App Store")
                        DemoAppRow(
                            title: "Daily Focus",
                            developer: "Northstar Studio",
                            symbol: "scope",
                            tint: .indigo
                        )
                        DemoAppRow(
                            title: "Pocket Journal",
                            developer: "Paper Kite",
                            symbol: "book.closed.fill",
                            tint: .orange
                        )
                        DemoAppRow(
                            title: "Skyline Weather",
                            developer: "Blue Hour Labs",
                            symbol: "cloud.sun.fill",
                            tint: .cyan
                        )
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        sectionHeading("Explore categories", subtitle: nil)
                        HStack(spacing: 10) {
                            categoryTile("Games", symbol: "gamecontroller.fill", tint: .purple)
                            categoryTile("Creativity", symbol: "paintpalette.fill", tint: .pink)
                            categoryTile("Productivity", symbol: "checkmark.circle.fill", tint: .green)
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("App Store")
            .navigationBarTitleDisplayMode(.large)
        }
    }

    private func sectionHeading(_ title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.title2.bold())
            if let subtitle {
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }

    private func categoryTile(_ title: String, symbol: String, tint: Color) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(tint)
            Text(title)
                .font(.caption.weight(.medium))
                .multilineTextAlignment(.center)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 76)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct FeaturedDemoCard: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("APP OF THE DAY")
                        .font(.caption.weight(.bold))
                        .opacity(0.8)
                    Text("Make room for\nwhat matters.")
                        .font(.title2.bold())
                }
                Spacer()
                Image(systemName: "sparkles.rectangle.stack.fill")
                    .font(.system(size: 48))
                    .foregroundStyle(.white.opacity(0.9))
            }
            Text("A sample editorial feature for the IPAForge App Store preview.")
                .font(.subheadline)
                .opacity(0.9)
        }
        .foregroundStyle(.white)
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [.indigo, .purple],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: RoundedRectangle(cornerRadius: 20)
        )
    }
}

private struct DemoAppRow: View {
    let title: String
    let developer: String
    let symbol: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(tint.gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(developer).font(.caption).foregroundStyle(.secondary)
                Text("Demo listing").font(.caption2).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("GET")
                .font(.caption.weight(.bold))
                .foregroundStyle(.blue)
                .padding(.horizontal, 16)
                .padding(.vertical, 7)
                .background(.blue.opacity(0.1), in: Capsule())
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
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
                        Text(environment.authPhase == .signedIn ? "Apple Account" : "Your Profile")
                            .font(.title3.bold())
                        Text(environment.authPhase == .signedIn
                             ? "Signed in"
                             : "Sign in is not available in this demo yet.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if environment.authPhase != .signedIn {
                            Button("Apple Account Sign In") {
                                destination = .login
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .listRowBackground(Color.clear)
                }

                Section("Your Library") {
                    profileRow("Downloads", symbol: "arrow.down.circle", destination: .downloads)
                }

                Section("Settings") {
                    profileRow("App Settings", symbol: "gearshape", destination: .settings)
                    profileRow("Activity Log", symbol: "text.alignleft", destination: .logs)
                }

                Section {
                    LabeledContent("Version", value: appVersion)
                }
            }
            .navigationTitle("Profile")
            .sheet(item: $destination) { destination in
                switch destination {
                case .login:
                    LoginView()
                case .downloads:
                    DownloadManagerView()
                case .settings:
                    SettingsView()
                case .logs:
                    LogViewerView()
                }
            }
        }
    }

    private var appVersion: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String
        return build.map { "\(version) (\($0))" } ?? version
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
    case settings
    case logs

    var id: String { rawValue }
}
