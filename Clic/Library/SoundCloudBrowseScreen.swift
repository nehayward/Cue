import SwiftUI
import SonosKit
import MusicSearchKit

struct SoundCloudBrowseScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(SonosService.self) private var sonosService
    @Environment(SoundCloudBrowseService.self) private var soundCloudBrowseService

    @State private var router = Router.browse
    
    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollView {
                if !soundCloudBrowseService.likedTracks.isEmpty {
                    Section {
                        VStack {
                            ScrollView(.horizontal) {
                                LazyHStack {
                                    ForEach(soundCloudBrowseService.likedTracks.prefix(10)) { item in
                                        VStack {
                                            PlayableArtworkView(item: item)
                                            Text(item.title)
                                                .foregroundStyle(.secondary)
                                                .font(.caption)
                                                .lineLimit(2, reservesSpace: true)
                                                .fontDesign(.rounded)
                                                .frame(maxWidth: .infinity, alignment: .leading)
                                        }
                                        .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, axis in
                                            return length / 2.5
                                        }
                                        .draggable(item)
                                    }
                                }
                                .padding(.horizontal, 16)
                            }
                            .scrollIndicators(.hidden)
                            .scrollClipDisabled()
                            PlayAllButtonView(item: .soundCloudLikes)
                                .padding(.horizontal, 16)
                        }
                    } header: {
                        let item = PlayableContent.soundCloudLikes
                        NavigationLink(value: RouterDestination.playableList(title: "SoundCloud Liked Tracks", playAllItem: item, action: { offset in
                            // If we need more tracks and can load more, load them
                            if offset >= soundCloudBrowseService.likedTracks.count && soundCloudBrowseService.canLoadMore {
                                await soundCloudBrowseService.loadMoreTracks()
                            }
                            // Return the tracks up to the requested offset
                            return Array(soundCloudBrowseService.likedTracks.prefix(offset + 50))
                        })) {
                            HStack(spacing: 2) {
                                Text("Liked Songs")
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .padding(.horizontal, 16)
                    }
                    .listRowBackground(Color.clear)
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
                } else if !soundCloudBrowseService.isLoading, soundCloudBrowseService.likedTracks.isEmpty {
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
            .listStyle(.plain)
            .fontDesign(.rounded)
            .foregroundStyle(.primary)
            .navigationTitle("SoundCloud Library")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await soundCloudBrowseService.updateLikedTracks()
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
                Task {
                    await soundCloudBrowseService.refresh()
                }
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
