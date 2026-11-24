import SwiftUI

@MainActor
final class AppEnvironment: ObservableObject {
    let logger = LoggingService()
    let anisette = AnisetteService()
    let authentication = AuthenticationService()
    let appStore = AppStoreService()
    let downloads = DownloadService()
    let export = ExportService()
    @Published var authPhase: AuthPhase = .signedOut
    @Published var authMessage = ""
    @Published var useDarkMode = false
    @Published var country = "us"

    var colorScheme: ColorScheme? {
        useDarkMode ? .dark : nil
    }

    init() {
        logger.log(.info, "Application launched.")
    }

    func cancelLogin() {
        authentication.cancelLogin()
        authPhase = .signedOut
        logger.log(.warning, "Login cancelled.")
    }
}
