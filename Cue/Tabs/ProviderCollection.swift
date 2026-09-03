import MusicSearchKit
import SwiftUI

/// One of the collections a provider's library is split into when it has a
/// sidebar section of its own — Plex's Artists, Albums, Songs and Playlists.
enum ProviderCollection: String, CaseIterable, Hashable, Codable {
    case artists
    case albums
    case songs
    case playlists

    var title: String {
        switch self {
        case .artists: "Artists"
        case .albums: "Albums"
        case .songs: "Songs"
        case .playlists: "Playlists"
        }
    }

    var systemImage: String {
        switch self {
        case .artists: "music.mic"
        case .albums: "square.stack"
        case .songs: "music.note"
        case .playlists: "rectangle.stack.badge.play"
        }
    }
}

extension MediaSearchService {
    /// The collections this provider's sidebar section is split into. Empty
    /// for a provider that only gets the one tab, its library's front page.
    /// Add a provider here — and an arm to `ProviderCollectionTabScreen` —
    /// when its browse service can page each collection on its own.
    var tabCollections: [ProviderCollection] {
        switch self {
        case .plex: [.artists, .albums, .songs, .playlists]
        default: []
        }
    }

    /// Whether the user can add this provider to the tab view at all: only
    /// providers whose library splits into collections, so the tabs never
    /// share the Browse tab's navigation state (each collection tab carries
    /// its own `Router`).
    var canBeTab: Bool {
        isBrowseSupported && !tabCollections.isEmpty
    }

    /// What a tab of this provider is written under in the customization
    /// sheet: the collections its sidebar section carries.
    var tabCollectionsDescription: String {
        tabCollections.map(\.title).formatted(.list(type: .and, width: .narrow))
    }

    /// The `customizationID` of this provider's own tab. A stable string the
    /// system keeps the user's sidebar edits under.
    var tabCustomizationID: String {
        "cue.tab.\(rawValue)"
    }

    func tabCustomizationID(for collection: ProviderCollection) -> String {
        "cue.tab.\(rawValue).\(collection.rawValue)"
    }
}
