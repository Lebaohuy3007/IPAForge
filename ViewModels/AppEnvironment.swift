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
        let anisette = AnisetteService(identityStore: accountVault)
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
            logger.logLogin(.info, "Fetching Anisette v3 data.")
            let anisetteHeaders = try await anisette.fetchAnisetteV3(serverURL: server.url)
            guard loginAttemptID == attemptID else { throw CancellationError() }
            let account = try await authentication.startLogin(
                appleID: appleID,
                password: password,
                anisetteHeaders: anisetteHeaders
            )
            guard loginAttemptID == attemptID else { throw CancellationError() }
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

    private func restoreSelectedAccount() async {
        guard let selectedID = selectedStoredAccountID else {
            return
        }
        do {
            guard let account = try accountVault.accounts().first(where: { $0.id == selectedID }) else {
                throw AppleAccountVaultError.accountNotFound
            }
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
        selectedStoredAccountID = restoredAccount.id
        authPhase = .signedIn
        logger.logLogin(.success, "Restored Apple session and fetched Developer Teams.")
    }
}
