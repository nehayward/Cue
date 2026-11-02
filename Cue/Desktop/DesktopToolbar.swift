import MusicSearchKit
import SonosKit
import SwiftUI

/// The row above the Mac window's page (`DesktopShell`): Back and Forward
/// through whichever page shows, and the one search field, as DaftMusic and
/// Spotify have it, rather than a field on the Search tab alone.
struct DesktopToolbar: View {
    @State private var desktop = DesktopState.shared

    var body: some View {
        let router = desktop.currentRouter

        HStack(spacing: 10) {
            Button {
                router.goBack()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(DesktopIconButtonStyle(side: 44, isFilled: true))
            .disabled(!router.canGoBack)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back (⌘[)")
            .accessibilityLabel("Back")

            Button {
                router.goForward()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.body.weight(.semibold))
            }
            .buttonStyle(DesktopIconButtonStyle(side: 44, isFilled: true))
            .disabled(!router.canGoForward)
            .keyboardShortcut("]", modifiers: .command)
            .help("Forward (⌘])")
            .accessibilityLabel("Forward")

            DesktopSearchField()
        }
    }
}

/// The window's search field. Typing (or clicking in) shows the Search tab,
/// whose results follow `MusicSearchService.query`; the arrow keys, Return
/// and Escape are passed on to it (`SearchActivator.relay`), and ⌘F or a
/// request for Search's field puts the cursor here.
struct DesktopSearchField: View {
    @State private var musicSearchService = MusicSearchService.shared
    @State private var desktop = DesktopState.shared
    @State private var offline = OfflineMode.shared
    @FocusState private var isFocused: Bool
    @State private var answeredRequest = SearchActivator.shared.requestCount
    @State private var isHovering = false

    private var isOnSearch: Bool { desktop.isShowing(.search) }

    var body: some View {
        @Bindable var musicSearchService = musicSearchService

        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField(
                offline.isActive ? "Search Downloads" : "Find something to play",
                text: $musicSearchService.query
            )
            .textFieldStyle(.plain)
            .focused($isFocused)
            .autocorrectionDisabled()
            .onKeyPress(.downArrow, phases: [.down, .repeat]) { _ in relay(.down) }
            .onKeyPress(.upArrow, phases: [.down, .repeat]) { _ in relay(.up) }
            .onKeyPress(.return) { relay(.select) }
            // Lets go of the chosen result and empties the field.
            .onKeyPress(.escape) {
                _ = relay(.cancel)
                guard !musicSearchService.query.isEmpty else { return .ignored }
                musicSearchService.query = ""
                return .handled
            }

        }
        .font(.body)
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(DesktopStyle.card, in: .capsule)
        .overlay {
            Capsule()
                .strokeBorder(Color("Accent"), lineWidth: 2)
                .opacity(isFocused ? 1 : 0)
        }
        .overlay {
            Capsule()
                .fill(DesktopStyle.hover)
                .opacity(isHovering && !isFocused ? 1 : 0)
                .allowsHitTesting(false)
        }
        .onHover { isHovering = $0 }
        .contentShape(.capsule)
        .onTapGesture {
            isFocused = true
        }
        .animation(.easeOut(duration: 0.15), value: isFocused)
        // A query, or the field taken, brings up Search.
        .onChange(of: musicSearchService.query) { _, query in
            if !query.isEmpty, !isOnSearch {
                desktop.select(.search)
            }
        }
        .onChange(of: isFocused) { _, focused in
            if focused, !isOnSearch {
                desktop.select(.search)
            }
        }
        // ⌘F, or Search chosen again in the sidebar.
        .onChange(of: SearchActivator.shared.requestCount) { _, count in
            guard count != answeredRequest else { return }
            answeredRequest = count
            isFocused = true
        }
    }

    /// Passes a key to the results while Search shows.
    private func relay(_ key: SearchActivator.RelayedKey) -> KeyPress.Result {
        guard isOnSearch else { return .ignored }
        SearchActivator.shared.relay(key)
        return .handled
    }
}
