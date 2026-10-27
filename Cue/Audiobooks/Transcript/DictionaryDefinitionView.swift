import SwiftUI

/// A word's definition set by Cue, for the Mac: there UIKit's dictionary
/// page (`UIReferenceLibraryViewController`) only opens Dictionary, so the
/// entry's text comes from the system dictionary through the Mac bridge
/// (`MacBridgeable.definition(of:)`) and is laid out here
/// (`DictionaryEntry`), with the way to the whole entry in Dictionary. On
/// iPhone and iPad the page itself shows instead.
struct DictionaryDefinitionView: View {
    let term: String
    /// Shows a close button, for Read Along's card.
    var onClose: (() -> Void)?

    @Environment(\.openURL) private var openURL
    @State private var entry: DictionaryEntry?
    @State private var isLoaded = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if let entry {
                    content(entry)
                } else if isLoaded {
                    ContentUnavailableView(
                        "No Definition",
                        systemImage: "character.book.closed",
                        description: Text("The dictionary has no entry for “\(term)”.")
                    )
                } else {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)
                }
                if isLoaded, let url = Self.dictionaryURL(for: term) {
                    Button("Open in Dictionary", systemImage: "arrow.up.forward.app") {
                        openURL(url)
                    }
                    .font(.subheadline)
                    .padding(.top, 6)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) {
            if let onClose {
                Button("Close", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
                    .padding(14)
            }
        }
        .task(id: term) { await load() }
    }

    @ViewBuilder
    private func content(_ entry: DictionaryEntry) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(entry.headword ?? term)
                .font(.title2.bold())
            if let pronunciation = entry.pronunciation {
                Text(pronunciation)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.trailing, onClose == nil ? 0 : 28)
        ForEach(Array(entry.parts.enumerated()), id: \.offset) { _, part in
            switch part {
            case let .partOfSpeech(label, rest):
                Text("\(Text(label).italic().bold())\(Text(verbatim: rest.isEmpty ? "" : " " + rest))")
                    .padding(.top, 6)
            case let .sense(number, definition):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(number)
                        .bold()
                        .monospacedDigit()
                        .frame(minWidth: 14, alignment: .trailing)
                    Text(definition)
                }
            case let .subsense(definition):
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(verbatim: "•")
                        .foregroundStyle(.secondary)
                    Text(definition)
                }
                .padding(.leading, 22)
            case let .section(title, rest):
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(rest)
                }
                .padding(.top, 6)
            case let .text(text):
                Text(text)
            }
        }
        .textSelection(.enabled)
    }

    private func load() async {
        entry = nil
        isLoaded = false
        entry = await Self.definition(of: term).map(DictionaryEntry.init)
        isLoaded = true
    }

    private static func definition(of term: String) async -> String? {
#if targetEnvironment(macCatalyst)
        guard let bridge = MenuAppLaunchAtLoginManager.shared.bridge else { return nil }
        return await Task.detached(priority: .userInitiated) {
            bridge.definition(of: term)
        }.value
#else
        return nil
#endif
    }

    /// Dictionary, open on the word.
    private static func dictionaryURL(for term: String) -> URL? {
        term.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed).flatMap { URL(string: "dict://\($0)") }
    }
}
