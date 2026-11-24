import SwiftUI

@main
struct AppStoreIPADownloaderApp: App {
    @StateObject private var environment = AppEnvironment()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(environment)
                .preferredColorScheme(environment.colorScheme)
        }
    }
}
