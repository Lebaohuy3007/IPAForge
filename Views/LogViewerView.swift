import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            LogOutputView(logger: environment.logger)
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { environment.logger.clear() }
                        .disabled(environment.logger.entries.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = environment.logger.text
                    }
                    .disabled(environment.logger.entries.isEmpty)
                }
            }
        }
    }
}

private struct LogOutputView: View {
    @ObservedObject var logger: LoggingService

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Server Response")
                    .font(.headline)
                Spacer()
                Text("\(logger.entries.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal)
            .padding(.vertical, 12)

            Divider()

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 5) {
                        if logger.entries.isEmpty {
                            Text("No logs yet")
                                .foregroundStyle(.secondary)
                                .padding(.vertical, 4)
                        }
                        ForEach(logger.entries) { entry in
                            Text(entry.formatted)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(color(for: entry.level))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(entry.id)
                        }
                    }
                    .padding(12)
                }
                .onAppear { scrollToLatest(using: proxy) }
                .onChange(of: logger.entries.last?.id) { _ in
                    scrollToLatest(using: proxy)
                }
            }
        }
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .padding()
    }

    private func scrollToLatest(using proxy: ScrollViewProxy) {
        guard let latestID = logger.entries.last?.id else { return }
        DispatchQueue.main.async {
            proxy.scrollTo(latestID, anchor: .bottom)
        }
    }

    private func color(for level: LogLevel) -> Color {
        switch level {
        case .error: return .red
        case .warning: return .orange
        case .success: return .green
        case .info: return .primary
        }
    }
}
