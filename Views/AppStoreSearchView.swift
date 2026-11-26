import SwiftUI

struct AppStoreSearchView: View {
    @EnvironmentObject private var environment: AppEnvironment
    @State private var query = ""
    @State private var results: [AppRecord] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack {
                if isLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                        Text("Searching...")
                    }
                    .padding(.horizontal)
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).padding(.horizontal)
                }
                List(results) { app in
                    NavigationLink(value: app) {
                        AppRow(app: app)
                    }
                }
                .navigationDestination(for: AppRecord.self) { app in
                    AppDetailView(app: app)
                }
            }
            .navigationTitle("App Store")
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Tên, Bundle ID hoặc App Store ID"
            )
            .onSubmit(of: .search) { search() }
        }
    }

    private func search() {
        let searchQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !searchQuery.isEmpty, !isLoading else { return }
        isLoading = true
        errorMessage = nil
        Task {
            do {
                results = try await environment.appStore.search(
                    searchQuery, country: environment.country
                )
                environment.logger.log(.info, "App Store search completed.")
            } catch {
                errorMessage = error.localizedDescription
                environment.logger.log(.error, "App Store search failed.")
            }
            isLoading = false
        }
    }
}

private struct AppRow: View {
    let app: AppRecord

    var body: some View {
        HStack(spacing: 12) {
            AsyncImage(url: app.iconURL) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Color.gray.opacity(0.2)
            }
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            VStack(alignment: .leading, spacing: 4) {
                Text(app.name).font(.headline)
                Text(app.developer).font(.subheadline).foregroundStyle(.secondary)
                Text("v\(app.version)").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
