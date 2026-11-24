import SwiftUI

struct LogViewerView: View {
    @EnvironmentObject private var environment: AppEnvironment

    var body: some View {
        NavigationStack {
            List(environment.logger.entries) { entry in
                Text(entry.formatted)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(color(for: entry.level))
                    .textSelection(.enabled)
            }
            .navigationTitle("Logs")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Clear") { environment.logger.clear() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Copy") {
                        UIPasteboard.general.string = environment.logger.text
                    }
                }
            }
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
