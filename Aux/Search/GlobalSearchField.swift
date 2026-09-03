import SonosKit
import SwiftUI

/// Which tab the window is showing. It has to be a binding rather than
/// `TabView`'s own private state because the always-on search field lives
/// outside the tabs and needs to pull the window to Search when a query starts.
enum AppTab: Hashable {
    case search
    case browse
    case test
}

/// The search field that sits above the `TabView` instead of inside any one
/// tab's navigation bar.
///
/// `Tab(role: .search)` looks like the native answer and isn't: it styles the
/// search *tab*, but the field still belongs to that tab's own bar and leaves
/// with it. Hosting a single field out here is what actually keeps it on
/// screen in every tab — and because it never unmounts, typing keeps focus and
/// the caret while the window switches tabs underneath it.
struct GlobalSearchField: View {
    @Binding var selectedTab: AppTab

    /// The singleton, not the environment: this is hosted by the `TabView`'s
    /// safe area, which sits outside what `withEnvironments()` installs on the
    /// tab content.
    private var musicSearchService: MusicSearchService { .shared }

    @FocusState private var focused: Bool

    var body: some View {
        @Bindable var musicSearchService = musicSearchService

        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)

            TextField("Search", text: $musicSearchService.query)
                .textFieldStyle(.plain)
                .focused($focused)
                .autocorrectionDisabled()
                .submitLabel(.search)

            if !musicSearchService.query.isEmpty {
                Button {
                    musicSearchService.query = ""
                    focused = true
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear Search")
            }
        }
        .frame(maxWidth: 800)
        .toolbarBackground(with: true, in: .capsule)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        // Results only exist on the Search tab, so a query typed while Browse
        // is up has to bring the window with it. Focus survives the switch
        // because this field belongs to neither tab.
        .onChange(of: musicSearchService.query) {
            guard !musicSearchService.query.isEmpty else { return }
            selectedTab = .search
        }
        .onSubmit { selectedTab = .search }
        .animation(.snappy, value: musicSearchService.query.isEmpty)
    }
}
