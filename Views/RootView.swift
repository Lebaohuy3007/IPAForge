import SwiftUI

struct RootView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        MainTabView()
            .environment(\.locale, environment.appLanguage.locale)
    }
}
