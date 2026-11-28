import SwiftUI
import StoreKit

enum AppLanguage: String, CaseIterable, Identifiable {
    case vietnamese
    case english

    var id: String { rawValue }
    var locale: Locale {
        Locale(identifier: self == .vietnamese ? "vi" : "en")
    }
    var titleKey: String {
        self == .vietnamese ? "🇻🇳 Vietnamese" : "🇺🇸 English"
    }

    static func forStorefront(countryCode: String?) -> AppLanguage {
        countryCode?.uppercased() == "VNM" ? .vietnamese : .english
    }
}

@MainActor
final class AppEnvironment: ObservableObject {
    let logger: LoggingService
    let anisette: AnisetteService
    let anisetteServers: AnisetteServerStore
    let authentication: AuthenticationService
    let accountVault: AppleAccountVault
    let appStore: AppStoreService
    let appStoreExperiments: AppStoreExperimentService
    let downloads: DownloadService
    let export = ExportService()
    @Published var authPhase: AuthPhase = .signedOut
    @Published var authMessage = ""
    @Published private(set) var selectedStoredAccountID: UUID?
    @Published private(set) var activeAccount: StoredAppleAccount?
    @Published private(set) var country: String
    @Published private(set) var appLanguage: AppLanguage
    @Published var languagePreference: AppLanguage? {
        didSet {
            UserDefaults.standard.set(languagePreference?.rawValue, forKey: Self.languagePreferenceKey)
            appLanguage = languagePreference ?? storefrontLanguage
        }
    }
    private var storefrontLanguage: AppLanguage = .english {
        didSet {
            if languagePreference == nil { appLanguage = storefrontLanguage }
        }
    }
    private static let languagePreferenceKey = "appLanguagePreference"
    private var loginAttemptID: UUID?

    init(accountVault: AppleAccountVault = AppleAccountVault()) {
        let logger = LoggingService()
        let appStore = AppStoreService()
        self.logger = logger
        self.appStore = appStore
        self.appStoreExperiments = AppStoreExperimentService(appStore: appStore, logger: logger)
        self.downloads = DownloadService(logger: logger)
        self.accountVault = accountVault
        country = Self.defaultAppStoreCountry
        let savedLanguage = UserDefaults.standard.string(forKey: Self.languagePreferenceKey)
            .flatMap(AppLanguage.init(rawValue:))
        languagePreference = savedLanguage
        appLanguage = savedLanguage ?? .english
        authentication = AuthenticationService(
            vault: accountVault,
            provider: StosSignAuthenticationProvider()
        )
        let anisette = AnisetteService(identityStore: accountVault, logger: logger)
        self.anisette = anisette
        self.anisetteServers = AnisetteServerStore(service: anisette)
        authentication.onVerificationStateChanged = { [weak self] isAwaiting in
            guard let self else { return }
            self.authPhase = isAwaiting ? .waitingFor2FA : .authenticating
        }
        do {
            let accounts = try accountVault.accounts()
            let selectedID = try accountVault.selectedAccountID()
            selectedStoredAccountID = accounts.contains(where: { $0.id == selectedID })
                ? selectedID
                : nil
            if let selectedAccount = accounts.first(where: { $0.id == selectedStoredAccountID }),
               let region = selectedAccount.storeCountry?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(),
               Self.supportedStoreCountries.contains(region) {
                country = region.lowercased()
            }
        } catch {
            logger.log(.error, "Could not load encrypted Apple Account records; secure storage is unavailable.")
        }
        logger.log(.info, "Application launched.")
        Task { [weak self] in
            let storefront = await Storefront.current
            self?.storefrontLanguage = AppLanguage.forStorefront(countryCode: storefront?.countryCode)
        }
        if selectedStoredAccountID != nil {
            Task { [weak self] in
                await self?.restoreSelectedAccount()
            }
        }
    }

    static var defaultAppStoreCountry: String {
        normalizedStoreCountry(Locale.current.region?.identifier ?? "US") ?? "us"
    }

    static let supportedStoreCountries: [String] = {
        Locale.Region.isoRegions
            .filter { $0.subRegions.isEmpty && $0.identifier.count == 2 }
            .map(\.identifier)
            .map { $0.uppercased() }
            .sorted { first, second in
                let firstName = Locale.current.localizedString(forRegionCode: first) ?? first
                let secondName = Locale.current.localizedString(forRegionCode: second) ?? second
                return firstName.localizedStandardCompare(secondName) == .orderedAscending
            }
    }()

    private static func normalizedStoreCountry(_ value: String) -> String? {
        let country = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard supportedStoreCountries.contains(country) else { return nil }
        return country.lowercased()
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
            logger.logLogin(.info, "Fetching Anisette v3 data.", correlationID: attemptID)
            logger.log(.info, "Developer Portal sign-in started. This does not create an App Store session.", correlationID: attemptID)
            logger.log(.info, "Anisette v3 | Stage: Header generation | Result: STARTED.", correlationID: attemptID)
            let anisetteHeaders = try await anisette.fetchAnisetteV3(
                serverURL: server.url,
                correlationID: attemptID
            )
            guard loginAttemptID == attemptID else { throw CancellationError() }
            logger.log(.success, "Anisette v3 | Stage: Header generation | Result: PASS.", correlationID: attemptID)
            let account = try await authentication.startLogin(
                appleID: appleID,
                password: password,
                anisetteHeaders: anisetteHeaders
            )
            guard loginAttemptID == attemptID else { throw CancellationError() }
            selectedStoredAccountID = account.id
            activeAccount = account
            authPhase = .signedIn
            logger.logLogin(.success, "Signed in and fetched Developer Teams.", correlationID: attemptID)
            logger.log(.success, "Developer Portal sign-in completed; Developer Teams were fetched. App Store sign-in was not performed.", correlationID: attemptID)
        } catch {
            guard loginAttemptID == attemptID else { throw CancellationError() }
            authPhase = .signedOut
            activeAccount = nil
            let nsError = error as NSError
            logger.log(.error, "Developer Portal sign-in failed | Error domain: \(nsError.domain) | Code: \(nsError.code) | \(LogSanitizer.sanitize(error.localizedDescription)).", correlationID: attemptID)
            throw error
        }
    }

    func submitVerificationCode(_ code: String) throws {
        try authentication.submitVerificationCode(code)
        authPhase = .authenticating
        logger.logLogin(.info, "Submitting Apple two-factor verification code.", correlationID: loginAttemptID)
        if let loginAttemptID {
            logger.log(.info, "Developer Portal 2FA submission started; verification code was not logged.", correlationID: loginAttemptID)
        }
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
            try accountVault.deleteAllAccounts()
            selectedStoredAccountID = nil
        } catch {
            logger.logLogin(.error, "Could not clear saved Apple sessions: \(error.localizedDescription)")
        }
        activeAccount = nil
        authPhase = .signedOut
        authMessage = ""
        logger.logLogin(.info, "Signed out.")
    }

    func restoreSavedSessionAfterAnisetteApproval() async {
        guard selectedStoredAccountID != nil, authPhase == .signedOut else { return }
        await restoreSelectedAccount()
    }

    private func restoreSelectedAccount() async {
        guard let selectedID = selectedStoredAccountID else {
            return
        }
        let correlationID = UUID()
        do {
            if let server = anisetteServers.selectedServer,
               try !anisetteServers.hasAnisetteApproval(serverID: server.id) {
                authPhase = .signedOut
                authMessage = "Approve the selected Anisette Server in its settings before restoring this Developer Portal session."
                logger.log(.warning, "Developer Portal session restore | BLOCKED | Anisette Server use has not been approved; no identity data was sent.", correlationID: correlationID)
                return
            }
            guard let account = try accountVault.accounts().first(where: { $0.id == selectedID }) else {
                throw AppleAccountVaultError.accountNotFound
            }
            try await restore(account, correlationID: correlationID)
        } catch {
            authPhase = .signedOut
            authMessage = "Could not restore the saved Apple session: \(LogSanitizer.sanitize(error.localizedDescription))"
            logger.logLogin(.error, "Session restore failed: \(error.localizedDescription)", correlationID: correlationID)
            let nsError = error as NSError
            logger.log(.error, "Developer Portal session restore failed | Error domain: \(nsError.domain) | Code: \(nsError.code) | \(LogSanitizer.sanitize(error.localizedDescription)).", correlationID: correlationID)
        }
    }

    private func restore(_ account: StoredAppleAccount, correlationID: UUID) async throws {
        guard let server = anisetteServers.selectedServer else {
            throw AnisetteServerError.notFound
        }
        authPhase = .authenticating
        authMessage = ""
        activeAccount = nil
        logger.logLogin(.info, "Refreshing Anisette v3 data for the saved Apple session.", correlationID: correlationID)
        logger.log(.info, "Developer Portal session restore started; this is not an App Store session.", correlationID: correlationID)
        let anisetteHeaders = try await anisette.fetchAnisetteV3(
            serverURL: server.url,
            correlationID: correlationID
        )
        logger.log(.success, "Anisette v3 | Stage: Header refresh | Result: PASS.", correlationID: correlationID)
        let restoredAccount = try await authentication.restore(
            account: account,
            anisetteHeaders: anisetteHeaders
        )
        activeAccount = restoredAccount
        selectedStoredAccountID = restoredAccount.id
        authPhase = .signedIn
        logger.logLogin(.success, "Restored Apple session and fetched Developer Teams.", correlationID: correlationID)
        logger.log(.success, "Developer Portal session restored and Developer Teams fetched. App Store session was not restored.", correlationID: correlationID)
    }
}
