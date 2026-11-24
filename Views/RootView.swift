import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        if environment.authPhase == .signedIn {
            MainTabView()
        } else {
            LoginView()
        }
    }
}
