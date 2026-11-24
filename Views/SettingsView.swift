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
                        SavedAccountRow(
                            account: account,
                            isSelected: environment.selectedStoredAccountID == account.id,
                            isDisabled: environment.authPhase == .authenticating,
                            onSelect: { select(account) },
                            onDelete: { accountToDelete = account }
                        )
                    }
                }
            } footer: {
                Text("Saved Apple sessions are encrypted with AES-256-GCM and stored in this device's Keychain. Selecting an account refreshes Anisette v3 data and validates the session with Apple.")
            }

            AuthenticationStatusSection(
                authPhase: environment.authPhase,
                activeAccount: environment.activeAccount,
                authMessage: environment.authMessage,
                onSignOut: { environment.signOut() }
            )
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

private struct SavedAccountRow: View {
    let account: StoredAppleAccount
    let isSelected: Bool
    let isDisabled: Bool
    let onSelect: () -> Void
    let onDelete: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack {
                accountDetails
                Spacer()
                selectionIndicator
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .swipeActions {
            Button("Delete", role: .destructive, action: onDelete)
        }
    }

    private var accountDetails: some View {
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
    }

    @ViewBuilder
    private var selectionIndicator: some View {
        if isSelected {
            Image(systemName: "checkmark")
                .foregroundStyle(.tint)
        }
    }
}

private struct AuthenticationStatusSection: View {
    let authPhase: AuthPhase
    let activeAccount: StoredAppleAccount?
    let authMessage: String
    let onSignOut: () -> Void

    var body: some View {
        Section("Authentication") {
            if authPhase == .authenticating {
                ProgressView("Restoring Apple session…")
            } else if authPhase == .signedIn, let activeAccount {
                SignedInAccountStatus(appleID: activeAccount.appleID)
                Button("Sign Out", action: onSignOut)
            } else {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(authMessage.isEmpty ? Color.secondary : Color.orange)
            }
        }
    }

    private var statusMessage: String {
        authMessage.isEmpty
            ? "Choose a saved Apple Account to restore its session."
            : authMessage
    }
}

private struct SignedInAccountStatus: View {
    let appleID: String

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill")
            Text("Signed in as \(appleID)")
        }
    }
}
