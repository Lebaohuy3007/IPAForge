import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let logger = LoggingService()
    let anisette: AnisetteService
    let anisetteServers: AnisetteServerStore
    let authentication: AuthenticationService
    let accountVault: AppleAccountVault
    let appStore = AppStoreService()
    let downloads = DownloadService()
    let export = ExportService()
    @Published var authPhase: AuthPhase = .signedOut
    @Published var authMessage = ""
    @Published private(set) var storedAccounts: [StoredAppleAccount] = []
    @Published private(set) var selectedStoredAccountID: UUID?
    @Published private(set) var activeAccount: StoredAppleAccount?
    @Published var accountVaultMessage = ""
    @Published private(set) var country: String
    private var loginAttemptID: UUID?

    init(accountVault: AppleAccountVault = AppleAccountVault()) {
        self.accountVault = accountVault
        country = Self.defaultAppStoreCountry
        authentication = AuthenticationService(
            vault: accountVault,
            provider: StosSignAuthenticationProvider()
        )
        let anisette = AnisetteService(identityStore: accountVault)
        self.anisette = anisette
        self.anisetteServers = AnisetteServerStore(service: anisette)
        authentication.onVerificationStateChanged = { [weak self] isAwaiting in
            guard let self else { return }
            self.authPhase = isAwaiting ? .waitingFor2FA : .authenticating
        }
        do {
            storedAccounts = try accountVault.accounts()
            let selectedID = try accountVault.selectedAccountID()
            selectedStoredAccountID = storedAccounts.contains(where: { $0.id == selectedID })
                ? selectedID
                : nil
            if let selectedAccount = storedAccounts.first(where: { $0.id == selectedStoredAccountID }),
               let region = selectedAccount.storeCountry?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
               region.count == 2 {
                country = region
            }
        } catch {
            accountVaultMessage = "Secure account storage is unavailable. Saved accounts were not loaded."
            logger.log(.error, "Could not load encrypted Apple Account records; secure storage is unavailable.")
        }
        logger.log(.info, "Application launched.")
        if selectedStoredAccountID != nil {
            Task { [weak self] in
                await self?.restoreSelectedAccount()
            }
        }
    }

    static var defaultAppStoreCountry: String {
        if #available(iOS 16, *) {
            return Locale.current.region?.lowercased() ?? "us"
        }
        return Locale.current.regionCode?.lowercased() ?? "us"
    }

    func selectStoredAccount(id: UUID) async throws {
        guard let account = storedAccounts.first(where: { $0.id == id }) else {
            throw AppleAccountVaultError.accountNotFound
        }
        try accountVault.setSelectedAccountID(id)
        selectedStoredAccountID = id
        if let region = account.storeCountry?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
           region.count == 2 {
            country = region
        } else {
            country = Self.defaultAppStoreCountry
        }
        do {
            try await restore(account)
        } catch {
            activeAccount = nil
            authPhase = .signedOut
            authMessage = "Could not restore the saved Apple session: \(LogSanitizer.sanitize(error.localizedDescription))"
            throw error
        }
    }

    func signIn(appleID: String, password: String) async throws {
        guard let server = anisetteServers.selectedServer else {
            throw AnisetteServerError.notFound
        }
        let attemptID = UUID()
        loginAttemptID = attemptID
        authPhase = .authenticating
        authMessage = ""
        defer {
            if loginAttemptID == attemptID {
                loginAttemptID = nil
            }
        }
        do {
            logger.logLogin(.info, "Fetching Anisette v3 data.")
            let anisetteHeaders = try await anisette.fetchAnisetteV3(serverURL: server.url)
            guard loginAttemptID == attemptID else { throw CancellationError() }
            let account = try await authentication.startLogin(
                appleID: appleID,
                password: password,
                anisetteHeaders: anisetteHeaders
            )
            guard loginAttemptID == attemptID else { throw CancellationError() }
            storedAccounts = (storedAccounts.filter { $0.id != account.id } + [account])
                .sorted { $0.id.uuidString < $1.id.uuidString }
            selectedStoredAccountID = account.id
            activeAccount = account
            authPhase = .signedIn
            logger.logLogin(.success, "Signed in and fetched Developer Teams.")
        } catch {
            guard loginAttemptID == attemptID else { throw CancellationError() }
            authPhase = .signedOut
            activeAccount = nil
            throw error
        }
    }

    func submitVerificationCode(_ code: String) throws {
        try authentication.submitVerificationCode(code)
        authPhase = .authenticating
        logger.logLogin(.info, "Submitting Apple two-factor verification code.")
    }

    func selectDeveloperTeam(id: String) throws {
        guard let account = activeAccount,
              account.teams.contains(where: { $0.id == id }) else {
            throw AuthenticationError.teamNotFound
        }
        let updatedAccount = StoredAppleAccount(
            id: account.id,
            appleID: account.appleID,
            sessionData: account.sessionData,
            teams: account.teams,
            selectedTeamID: id,
            savedPassword: nil,
            storeCountry: account.storeCountry
        )
        try accountVault.save(updatedAccount)
        activeAccount = updatedAccount
        storedAccounts = storedAccounts.map { $0.id == updatedAccount.id ? updatedAccount : $0 }
    }

    func deleteStoredAccount(id: UUID) throws {
        try accountVault.deleteAccount(id: id)
        storedAccounts = try accountVault.accounts()
        selectedStoredAccountID = try accountVault.selectedAccountID()
        if activeAccount?.id == id {
            authentication.signOut()
            activeAccount = nil
            authPhase = .signedOut
        }
    }

    func cancelLogin() {
        loginAttemptID = nil
        authentication.cancelLogin()
        authPhase = .signedOut
        authMessage = "Sign-in cancelled."
        logger.logLogin(.warning, "Apple Account sign-in cancelled.")
    }

    func signOut() {
        authentication.signOut()
        do {
            try accountVault.setSelectedAccountID(nil)
            selectedStoredAccountID = nil
        } catch {
            accountVaultMessage = error.localizedDescription
            logger.logLogin(.error, "Could not clear the selected saved session: \(error.localizedDescription)")
        }
        activeAccount = nil
        authPhase = .signedOut
        authMessage = ""
        logger.logLogin(.info, "Signed out.")
    }

    private func restoreSelectedAccount() async {
        guard let selectedID = selectedStoredAccountID,
              let account = storedAccounts.first(where: { $0.id == selectedID }) else {
            return
        }
        do {
            try await restore(account)
        } catch {
            authPhase = .signedOut
            authMessage = "Could not restore the saved Apple session: \(LogSanitizer.sanitize(error.localizedDescription))"
            logger.logLogin(.error, "Session restore failed: \(error.localizedDescription)")
        }
    }

    private func restore(_ account: StoredAppleAccount) async throws {
        guard let server = anisetteServers.selectedServer else {
            throw AnisetteServerError.notFound
        }
        authPhase = .authenticating
        authMessage = ""
        activeAccount = nil
        logger.logLogin(.info, "Refreshing Anisette v3 data for the saved Apple session.")
        let anisetteHeaders = try await anisette.fetchAnisetteV3(serverURL: server.url)
        let restoredAccount = try await authentication.restore(
            account: account,
            anisetteHeaders: anisetteHeaders
        )
        activeAccount = restoredAccount
        storedAccounts = storedAccounts.map { $0.id == restoredAccount.id ? restoredAccount : $0 }
        selectedStoredAccountID = restoredAccount.id
        authPhase = .signedIn
        logger.logLogin(.success, "Restored Apple session and fetched Developer Teams.")
    }
}
