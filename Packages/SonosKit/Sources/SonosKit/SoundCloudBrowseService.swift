import Foundation
import OrderedCollections
import MusicSearchKit

@MainActor
@Observable
public final class SoundCloudBrowseService {
    public static let shared = SoundCloudBrowseService()
    
    public var likedTracks: OrderedSet<PlayableContent> = []
    public var likedPlaylists: OrderedSet<PlayableContent> = []
    public var isLoadingTracks: Bool = false
    public var isLoadingPlaylists: Bool = false
    public var isLoadingMore: Bool = false
    public var isLoadingMorePlaylists: Bool = false
    public var error: String?

    // Cursor-based pagination state for tracks
    public var hasMoreTracks: Bool = true
    private var nextCursor: String?

    // Cursor-based pagination state for playlists
    public var hasMorePlaylists: Bool = true
    private var nextPlaylistCursor: String?

    private let musicSearchService = MusicSearchService.shared

    // Combined loading state for UI
    public var isLoading: Bool {
        return isLoadingTracks || isLoadingPlaylists
    }
    
    private init() {}
    
    /// Loads the initial batch of liked tracks
    public func updateLikedTracks() async {
        guard !isLoadingTracks else { return }

        isLoadingTracks = true
        error = nil
        nextCursor = nil
        hasMoreTracks = true

        let result = await musicSearchService.getSoundCloudLikedTracks(cursor: nil)
        // Cancelled by switching to another service: the empty result says
        // nothing about the account, so don't report it as signed out.
        guard !Task.isCancelled else {
            isLoadingTracks = false
            return
        }

        if result.tracks.isEmpty {
            self.error = "SoundCloud not authenticated. Please connect your SoundCloud account in settings."
            hasMoreTracks = false
        } else {
            likedTracks = OrderedSet(result.tracks)
            nextCursor = result.nextCursor
            hasMoreTracks = result.nextCursor != nil
            self.error = nil
        }

        isLoadingTracks = false
    }
    
    /// Loads the next page of liked tracks
    public func loadMoreTracks() async {
        guard !isLoadingMore && hasMoreTracks && !isLoadingTracks else { return }
        
        isLoadingMore = true
        error = nil
        
        let result = await musicSearchService.getSoundCloudLikedTracks(cursor: nextCursor)
        
        if result.tracks.isEmpty {
            hasMoreTracks = false
        } else {
            // Append new tracks to existing set
            for track in result.tracks {
                likedTracks.append(track)
            }
            nextCursor = result.nextCursor
            hasMoreTracks = result.nextCursor != nil
        }
        
        isLoadingMore = false
    }
    
    /// Refreshes all liked tracks and playlists from the beginning
    public func refresh() async {
        likedTracks.removeAll()
        likedPlaylists.removeAll()
        nextCursor = nil
        nextPlaylistCursor = nil
        hasMoreTracks = true
        hasMorePlaylists = true

        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.updateLikedTracks() }
            group.addTask { await self.updateLikedPlaylists() }
        }
    }
    
    /// Checks if there are more tracks available to load
    public var canLoadMore: Bool {
        return hasMoreTracks && !isLoadingTracks && !isLoadingMore
    }
    
    /// Returns the total number of tracks loaded so far
    public var loadedTrackCount: Int {
        return likedTracks.count
    }

    // MARK: - Playlist Methods

    /// Loads the initial batch of liked playlists
    public func updateLikedPlaylists() async {
        guard !isLoadingPlaylists else { return }

        isLoadingPlaylists = true
        error = nil
        nextPlaylistCursor = nil
        hasMorePlaylists = true

        let result = await musicSearchService.getSoundCloudLikedPlaylists(cursor: nil)
        guard !Task.isCancelled else {
            isLoadingPlaylists = false
            return
        }

        if result.playlists.isEmpty {
            hasMorePlaylists = false
        } else {
            likedPlaylists = OrderedSet(result.playlists)
            nextPlaylistCursor = result.nextCursor
            hasMorePlaylists = result.nextCursor != nil
        }

        isLoadingPlaylists = false
    }

    /// Loads the next page of liked playlists
    public func loadMorePlaylists() async {
        guard !isLoadingMorePlaylists && hasMorePlaylists && !isLoadingPlaylists else { return }

        isLoadingMorePlaylists = true
        error = nil

        let result = await musicSearchService.getSoundCloudLikedPlaylists(cursor: nextPlaylistCursor)

        if result.playlists.isEmpty {
            hasMorePlaylists = false
        } else {
            // Append new playlists to existing set
            for playlist in result.playlists {
                likedPlaylists.append(playlist)
            }
            nextPlaylistCursor = result.nextCursor
            hasMorePlaylists = result.nextCursor != nil
        }

        isLoadingMorePlaylists = false
    }

    /// Checks if there are more playlists available to load
    public var canLoadMorePlaylists: Bool {
        return hasMorePlaylists && !isLoadingPlaylists && !isLoadingMorePlaylists
    }

    /// Returns the total number of playlists loaded so far
    public var loadedPlaylistCount: Int {
        return likedPlaylists.count
    }
}
