import MusicSearchKit
import SwiftUI

/// Report a Problem ▸ View Log: the log file on this device, newest line
/// first, searchable, with errors and warnings in colour. For seeing what a
/// report will say before it's sent, and for reading on the phone what
/// would otherwise need Xcode.
struct LogViewerScreen: View {
    /// Newest first.
    @State private var entries: [LogEntry] = []
    @State private var isLoading = true
    @State private var searchText = ""
    @State private var problemsOnly = false

    private var shownEntries: [LogEntry] {
        entries.filter { entry in
            if problemsOnly, (entry.level ?? .info) < .warning {
                return false
            }
            guard !searchText.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(searchText)
                || entry.category.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        let shown = shownEntries
        List(shown) { entry in
            LogEntryRow(entry: entry)
        }
        .listStyle(.plain)
        .searchable(text: $searchText, prompt: "Search the Log")
        .navigationTitle("Log")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Toggle("Problems Only", systemImage: "exclamationmark.triangle", isOn: $problemsOnly)
                    ShareLink(
                        item: SupportReportFile(),
                        subject: Text(SupportReport.emailSubject),
                        preview: SharePreview("Cue Log", image: Image(systemName: "doc.text"))
                    ) {
                        Label("Share Log File", systemImage: "square.and.arrow.up")
                    }
                } label: {
                    Label("Options", systemImage: problemsOnly ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                }
            }
        }
        .overlay {
            if isLoading {
                ProgressView()
            } else if shown.isEmpty {
                if !searchText.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else if problemsOnly {
                    ContentUnavailableView("No Problems", systemImage: "checkmark.circle", description: Text("Nothing in the log is a warning or an error."))
                } else {
                    ContentUnavailableView("Nothing Logged", systemImage: "doc.text", description: Text("Cue hasn't logged anything on this device yet."))
                }
            }
        }
        .task {
            await load()
        }
        .refreshable {
            await load()
        }
    }

    private func load() async {
        entries = await Task.detached(priority: .userInitiated) {
            Array(LogStore.entries(in: LogStore.shared.recentText()).reversed())
        }.value
        isLoading = false
    }
}

private struct LogEntryRow: View {
    let entry: LogEntry

    var body: some View {
        if entry.isLaunch {
            Text(entry.message.trimmingCharacters(in: CharacterSet(charactersIn: "─ ")))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .listRowBackground(Color.secondary.opacity(0.12))
        } else {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    // The year is in the file; on the phone it's noise.
                    Text(entry.timestamp.dropFirst(5))
                        .monospacedDigit()
                    if !entry.category.isEmpty {
                        Text(entry.category)
                    }
                    Spacer()
                    if let level = entry.level, level >= .warning {
                        Text(level.label)
                            .bold()
                            .foregroundStyle(color)
                    }
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                Text(entry.message)
                    .font(.caption.monospaced())
                    .foregroundStyle(color)
            }
            .contextMenu {
                Button("Copy", systemImage: "doc.on.doc") {
                    UIPasteboard.general.string = "\(entry.timestamp) [\(entry.category)] \(entry.message)"
                }
            }
        }
    }

    private var color: Color {
        switch entry.level {
        case .error, .fault: .red
        case .warning: .orange
        case .debug: .secondary
        default: .primary
        }
    }
}
