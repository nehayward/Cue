import Foundation
import OrderedCollections
import MusicSearchKit

@MainActor
@Observable
public final class SoundCloudBrowseService {
    public static let shared = SoundCloudBrowseService()
    
    public var likedTracks: OrderedSet<PlayableContent> = []
    public var isLoading: Bool = false
    public var isLoadingMore: Bool = false
    public var error: String?
    
    // Cursor-based pagination state
    public var hasMoreTracks: Bool = true
    private var nextCursor: String?
    private let musicSearchService = MusicSearchService.shared
    
    private init() {}
    
    /// Loads the initial batch of liked tracks
    public func updateLikedTracks() async {
        guard !isLoading else { return }
        
        isLoading = true
        error = nil
        nextCursor = nil
        hasMoreTracks = true
        
        let result = await musicSearchService.getSoundCloudLikedTracks(cursor: nil)
        
        if result.tracks.isEmpty {
            self.error = "SoundCloud not authenticated. Please connect your SoundCloud account in settings."
            hasMoreTracks = false
        } else {
            likedTracks = OrderedSet(result.tracks)
            nextCursor = result.nextCursor
            hasMoreTracks = result.nextCursor != nil
            self.error = nil
        }
        
        isLoading = false
    }
    
    /// Loads the next page of liked tracks
    public func loadMoreTracks() async {
        guard !isLoadingMore && hasMoreTracks && !isLoading else { return }
        
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
    
    /// Refreshes all liked tracks from the beginning
    public func refresh() async {
        likedTracks.removeAll()
        nextCursor = nil
        hasMoreTracks = true
        await updateLikedTracks()
    }
    
    /// Checks if there are more tracks available to load
    public var canLoadMore: Bool {
        return hasMoreTracks && !isLoading && !isLoadingMore
    }
    
    /// Returns the total number of tracks loaded so far
    public var loadedTrackCount: Int {
        return likedTracks.count
    }
}
