import SwiftUI
import SonosKit
import MusicSearchKit

struct SonosRadioBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(SonosRadioBrowseService.self) private var sonosRadioBrowseService

    @State private var router = Router.browse

    private var isEmpty: Bool {
        sonosRadioBrowseService.populatedSections.isEmpty
    }

    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if isEmpty, let error = sonosRadioBrowseService.error {
                    errorSection(error)
                } else if isEmpty, !sonosRadioBrowseService.isLoading {
                    emptySection
                } else {
                    if let error = sonosRadioBrowseService.error {
                        staleNotice(error)
                    }
                    ForEach(sonosRadioBrowseService.populatedSections) { section in
                        sectionView(for: section)
                    }
                }
            }
            .listSectionSpacing(4)
            .listStyle(.plain)
            .headerProminence(.increased)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("Sonos Radio")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await sonosRadioBrowseService.load()
            }
            .toolbar {
                ToolbarItem {
                    SettingsToolbarButton()
                        .environment(router)
                }
                ToolbarItem {
                    MediaSelector()
                        .environment(router)
                }
            }
#if !targetEnvironment(macCatalyst)
            .addDismiss {
                dismiss()
                Router.main.inspectorSheet = nil
            }
#endif
            .refreshable {
                await sonosRadioBrowseService.refresh()
            }
            .withAppRouter()
        }
        .overlay {
            if sonosRadioBrowseService.isLoading, isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task { await sonosRadioBrowseService.load() }
        }
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
    }

    @ViewBuilder
    private func sectionView(for section: SonosRadioSection) -> some View {
        let items = section.items
        Section {
            NavigationLink(value: RouterDestination.playableList(
                title: section.title,
                showSectionIndex: false,
                action: { _ in
                    await sonosRadioBrowseService.allStations(for: section)
                }
            )) {
                Text(section.title)
                    .fontDesign(.rounded)
                    .fontWeight(.semibold)
            }
            .tag(UUID().uuidString)

            LazyVGrid(columns: [.init(), .init()]) {
                ForEach(items.prefix(sonosRadioBrowseService.previewCount)) { item in
                    PlayableContentRowView(item: item)
                        .buttonStyle(.plain)
                        .geometryGroup()
                }
            }
        }
        .listRowInsets(.default)
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowSpacing(0)
    }

    /// Compact banner shown above the sections when a refresh failed but
    /// previously loaded content is still on screen.
    @ViewBuilder
    private func staleNotice(_ message: String) -> some View {
        Section {
            Label(message, systemImage: "wifi.exclamationmark")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .listRowSeparator(.hidden)
        .listSectionSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func errorSection(_ error: String) -> some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 48))
                    .foregroundColor(.orange)

                Text("Error Loading Sonos Radio")
                    .font(.headline)

                Text(error)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Button("Try Again") {
                    Task { await sonosRadioBrowseService.load() }
                }
                .buttonStyle(.borderedProminent)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private var emptySection: some View {
        Section {
            VStack(spacing: 16) {
                Image(systemName: "dot.radiowaves.left.and.right")
                    .font(.system(size: 48))
                    .foregroundColor(.secondary)

                Text("No Stations")
                    .font(.headline)

                Text("Pull to refresh to load Sonos Radio stations.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

#Preview {
    SonosRadioBrowseScreen()
        .withEnvironments()
}
