import Foundation
import OrderedCollections
import SonosKit
import MusicSearchKit

@MainActor
@Observable
public final class SoundCloudBrowseService {
    public static let shared = SoundCloudBrowseService()
    
    public var likedTracks: OrderedSet<PlayableContent> = []
    public var isLoading: Bool = false
    public var error: String?
    
    private let musicSearchService = MusicSearchService.shared
    
    private init() {}
    
    public func updateLikedTracks() async {
        isLoading = true
        error = nil
        
        do {
            let tracks = await musicSearchService.getSoundCloudLikedTracks()
            
            if tracks.isEmpty {
                self.error = "SoundCloud not authenticated. Please connect your SoundCloud account in settings."
            } else {
                likedTracks = OrderedSet(tracks)
                self.error = nil
            }
        } catch {
            self.error = "SoundCloud not authenticated. Please connect your SoundCloud account in settings."
        }
        
        isLoading = false
    }
    
    public func refresh() async {
        likedTracks.removeAll()
        await updateLikedTracks()
    }
}
