import SwiftUI
import SonosKit
import MusicSearchKit

struct SoundCloudBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(SoundCloudBrowseService.self) private var soundCloudBrowseService
    
    @State private var router = Router()
    @State private var isLoading: Bool = true
    
    var body: some View {
        NavigationStack(path: $router.path) {
            List {
                if !soundCloudBrowseService.likedTracks.isEmpty {
                    Section {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(soundCloudBrowseService.likedTracks.prefix(10)) { item in
                                    PlayableArtworkView(item: item)
                                        .containerRelativeFrame(.horizontal, count: 4, spacing: 4)
                                        .listRowInsets(EdgeInsets())
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                    } header: {
                        NavigationLink(value: RouterDestination.playableList(title: "SoundCloud Liked Tracks", action: { offset in
                            // If we need more tracks and can load more, load them
                            if offset >= soundCloudBrowseService.likedTracks.count && soundCloudBrowseService.canLoadMore {
                                await soundCloudBrowseService.loadMoreTracks()
                            }
                            // Return the tracks up to the requested offset
                            return Array(soundCloudBrowseService.likedTracks.prefix(offset + 50))
                        })) {
                            HStack {
                                Label("Liked Tracks", systemImage: "heart.fill")
                                Spacer()
                                if soundCloudBrowseService.canLoadMore {
                                    Text("\(soundCloudBrowseService.loadedTrackCount)+")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                Image(systemName: "chevron.right")
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                } else if let error = soundCloudBrowseService.error {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "exclamationmark.triangle")
                                .font(.system(size: 48))
                                .foregroundColor(.orange)
                            
                            Text("Error Loading SoundCloud")
                                .font(.headline)
                            
                            Text(error)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Button("Try Again") {
                                Task {
                                    await soundCloudBrowseService.updateLikedTracks()
                                }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                        .padding()
                    }
                } else if !isLoading {
                    Section {
                        VStack(spacing: 16) {
                            Image(systemName: "heart.slash")
                                .font(.system(size: 48))
                                .foregroundColor(.secondary)
                            
                            Text("No Liked Tracks")
                                .font(.headline)
                            
                            Text("Your SoundCloud liked tracks will appear here when you authenticate.")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
            }
            .headerProminence(.increased)
            .miniPlayerOnScrollHandler()
            .listStyle(.sidebar)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("SoundCloud Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                isLoading = true
                await soundCloudBrowseService.updateLikedTracks()
                isLoading = false
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
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
                await soundCloudBrowseService.refresh()
            }
            .withAppRouter()
        }
        .overlay {
            if soundCloudBrowseService.isLoading, soundCloudBrowseService.likedTracks.isEmpty {
                ProgressView()
                    .frame(maxWidth: .infinity, alignment: .center)
                    .listRowBackground(Color.clear)
            }
        }
        .environment(router)
        .withSheetDestinations(sheetDestinations: $router.presentedSheet) {
            Task {
                await soundCloudBrowseService.updateLikedTracks()
            }
        }
    }
}

#Preview {
    SoundCloudBrowseScreen()
        .withEnvironments()
}
