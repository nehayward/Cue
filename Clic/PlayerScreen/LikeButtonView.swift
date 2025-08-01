import MusicSearchKit
import SonosKit
import SwiftUI

struct LikeButtonView: View {
    var group: GroupRoom
    
    @State private var isFavorite: Bool?
    
    var body: some View {
        if group.coordinatorRoom.track.musicService == .spotify {
            Button {
                if isFavorite ?? false {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        await MusicSearchService.shared.deleteSpotifyTrack(id: group.coordinatorRoom.track.trackID)
                        isFavorite = await MusicSearchService.shared.isSpotifyTrackSaved(id: group.coordinatorRoom.track.trackID)
                    }
                } else {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        await MusicSearchService.shared.saveSpotifyTrack(id: group.coordinatorRoom.track.trackID)
                        isFavorite = await MusicSearchService.shared.isSpotifyTrackSaved(id: group.coordinatorRoom.track.trackID)
                    }
                }
            } label: {
                Image(systemName: "heart")
                    .symbolVariant(isFavorite ?? false ? .fill : .none)
                    .foregroundStyle(MusicService.spotify.brandColor.gradient)
                    .help("Favorite Song")
                    .accessibilityLabel("Favorite Song")
            }
            .task(id: group.coordinatorRoom.track.id) {
                if group.coordinatorRoom.track.musicService == .spotify {
                    isFavorite = await MusicSearchService.shared.isSpotifyTrackSaved(id: group.coordinatorRoom.track.trackID)
                } else {
                    isFavorite = nil
                }
            }
        }
        
        if group.coordinatorRoom.track.musicService == .soundcloud {
            Button {
                if isFavorite ?? false {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        await MusicSearchService.shared.unlikeSoundCloudTrack(id: group.coordinatorRoom.track.trackID)
                        isFavorite = await MusicSearchService.shared.isSoundCloudTrackLiked(id: group.coordinatorRoom.track.trackID)
                    }
                } else {
                    Task {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        await MusicSearchService.shared.likeSoundCloudTrack(id: group.coordinatorRoom.track.trackID)
                        isFavorite = await MusicSearchService.shared.isSoundCloudTrackLiked(id: group.coordinatorRoom.track.trackID)
                    }
                }
            } label: {
                Image(systemName: "heart")
                    .symbolVariant(isFavorite ?? false ? .fill : .none)
                    .foregroundStyle(MusicService.soundcloud.brandColor.gradient)
                    .help("Like Song")
                    .accessibilityLabel("Like Song")
            }
            .task(id: group.coordinatorRoom.track.id) {
                if group.coordinatorRoom.track.musicService == .soundcloud {
                    isFavorite = await MusicSearchService.shared.isSoundCloudTrackLiked(id: group.coordinatorRoom.track.trackID)
                } else {
                    isFavorite = nil
                }
            }
        }
        
        // MARK: add Back when it's working
        //                    if group.coordinatorRoom.track.musicService == .apple {
        //                        Button {
        //                            Task {
        //                                let favorite = isFavorite ?? false
        //                                try? await AppleMusicAPI().updateFavoriteStatus(songId: group.coordinatorRoom.track.trackID, favorite: !favorite)
        //                                isFavorite = try? await AppleMusicAPI().isFavorite(songId: group.coordinatorRoom.track.trackID)
        //                            }
        //                        } label: {
        //                            Image(systemName: "star")
        //                                .symbolVariant(isFavorite ?? false ? .fill : .none)
        //                                .foregroundStyle(.red.gradient)
        //                                .animation(.spring, value: isFavorite)
        //                        }
        //                    }
        // MARK: add Back when it's working
//            if group.coordinatorRoom.track.musicService == .apple {
//                isFavorite = try? await AppleMusicAPI().isFavorite(songId: group.coordinatorRoom.track.trackID)
//            } else {
//                isFavorite = nil
//            }
    }
}
