import SwiftUI

struct SavedAccountsView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var accountToDelete: StoredAppleAccount?
    @State private var errorMessage = ""

    var body: some View {
        List {
            if !environment.accountVaultMessage.isEmpty {
                Section {
                    Text(environment.accountVaultMessage)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if environment.storedAccounts.isEmpty {
                    Text("No saved Apple Accounts.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(environment.storedAccounts) { account in
                        Button {
                            select(account)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(account.appleID)
                                        .foregroundStyle(.primary)
                                    Text("\(account.teams.count) developer team(s)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    if let selectedTeam = account.teams.first(where: { $0.id == account.selectedTeamID }) {
                                        Text("Selected team: \(selectedTeam.name)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                if environment.selectedStoredAccountID == account.id {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .disabled(environment.authPhase == .authenticating)
                        .swipeActions {
                            Button("Delete", role: .destructive) {
                                accountToDelete = account
                            }
                        }
                    }
                }
            } footer: {
                Text("Saved Apple sessions are encrypted with AES-256-GCM and stored in this device's Keychain. Selecting an account refreshes Anisette v3 data and validates the session with Apple.")
            }

            Section("Authentication") {
                if environment.authPhase == .authenticating {
                    ProgressView("Restoring Apple session…")
                } else if environment.authPhase == .signedIn,
                          let account = environment.activeAccount {
                    Label("Signed in as \(account.appleID)", systemImage: "checkmark.circle.fill")
                    Button("Sign Out") {
                        environment.signOut()
                    }
                } else {
                    Text(environment.authMessage.isEmpty
                         ? "Choose a saved Apple Account to restore its session."
                         : environment.authMessage)
                        .font(.caption)
                        .foregroundStyle(environment.authMessage.isEmpty ? .secondary : .orange)
                }
            }
        }
        .navigationTitle("Saved Accounts")
        .confirmationDialog("Delete saved account?", isPresented: Binding(
            get: { accountToDelete != nil },
            set: { if !$0 { accountToDelete = nil } }
        )) {
            Button("Cancel", role: .cancel) {
                accountToDelete = nil
            }
            Button("Delete", role: .destructive) {
                if let accountToDelete {
                    delete(accountToDelete)
                }
            }
        } message: {
            Text("The encrypted session for \(accountToDelete?.appleID ?? "this account") will be removed from this device.")
        }
        .alert("Account storage error", isPresented: Binding(
            get: { !errorMessage.isEmpty },
            set: { if !$0 { errorMessage = "" } }
        )) {
            Button("OK") { errorMessage = "" }
        } message: {
            Text(errorMessage)
        }
    }

    private func select(_ account: StoredAppleAccount) {
        Task {
            do {
                try await environment.selectStoredAccount(id: account.id)
            } catch {
                errorMessage = LogSanitizer.sanitize(error.localizedDescription)
                environment.authMessage = errorMessage
            }
        }
    }

    private func delete(_ account: StoredAppleAccount) {
        do {
            try environment.deleteStoredAccount(id: account.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        accountToDelete = nil
    }
}
