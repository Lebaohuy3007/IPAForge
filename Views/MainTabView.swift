import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            AppStoreSearchView()
                .tabItem { Label("Search", systemImage: "magnifyingglass") }
            DownloadManagerView()
                .tabItem { Label("Downloads", systemImage: "arrow.down.circle") }
            LogViewerView()
                .tabItem { Label("Logs", systemImage: "text.alignleft") }
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}
