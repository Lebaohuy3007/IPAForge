import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            Form {
                Section("Appearance") {
                    Toggle("Dark Mode", isOn: $environment.useDarkMode)
                }
                Section("App Store") {
                    TextField("Country Code", text: $environment.country)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section("Account") {
                    Button("Sign Out", role: .destructive) {
                        environment.cancelLogin()
                    }
                }
                Section("Status") {
                    Text("Apple Account sign-in and IPA package delivery are not implemented. The app does not simulate success.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
        }
    }
}
