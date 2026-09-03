import Observation
import SonosKit

@Observable
final class PlaylistContainer {
    static var shared = PlaylistContainer()
    
    var playlists: [PlayableContent] = []
}
