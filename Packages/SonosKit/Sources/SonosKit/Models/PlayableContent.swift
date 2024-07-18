import Foundation
import CoreTransferable
import UniformTypeIdentifiers

public struct PlayableContent: Equatable, Codable, Hashable, Identifiable {
    public var id: String { content.id }
    public let title: String
    public let subtitle: String
    public let artwork: URL?
    public let content: MediaContent
    public var metadata: PlayableContentMetadata?

    public var trackID: String { content.id + (metadata?.position?.description ?? "") }

    public init(
        title: String,
        subtitle: String,
        artwork: URL?,
        content: MediaContent,
        metadata: PlayableContentMetadata? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.artwork = artwork
        self.content = content
        self.metadata = metadata
    }

    public var shareURL: URL {
        // TODO: Check
        #warning("DOULBE CHECK THIS")
        guard content.service != .unknown else { return URL(string: "clic://")! }
        guard let musicService = content.service.name?.lowercased() else { return  URL(string: "clic://")!  }
        return URL(string: "clic://play/\(musicService)/\(content.type)/\(id)")!
    }

    public var uri: String {
        switch (content.type, content.service) {
        case (.track, .spotify):
            return "x-sonos-spotify:spotify%3atrack%3a\(id)?sid=9&amp;flags=8224&amp;sn=7"
        case (.album, .spotify):
            return "x-rincon-cpcontainer:1004206cspotify%3aalbum%3a\(id)?sid=12&amp;flags=8300&amp;sn=3"
        case (.playlist, .spotify):
            return "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a\(id)?sid=12&amp;flags=44&amp;sn=3"
        case (.track, .apple):
            return "x-sonos-http:song%3a\(id).mp4?sid=204&amp;flags=8224&amp;sn=5"
        case (.libraryTrack, .apple):
            return "x-sonos-http:librarytrack%3a\(id)?sid=204&amp;flags=8232&amp;sn=4"
        case (.libraryAlbum, .apple):
            return "x-rincon-cpcontainer:1004206clibraryalbum%3a\(id)?sid=204&amp;flags=8300&amp;sn=4"
        case (.album, .apple):
            return "x-rincon-cpcontainer:1004206calbum%3a\(id)?sid=204&amp;flags=8300&amp;sn=5"
        case (.playlist, .apple):
            return "x-rincon-cpcontainer:1006206cplaylist%3a\(id)?sid=204&amp;flags=8300&amp;sn=5"
        case (.favorite, _):
            return id
        case (_, .library):
            return id
        case (.track, .plex):
            return "x-sonosapi-hls-static:10036020\(id)%3Atrack?sid=212&amp;flags=24616&amp;sn=9"
        case (.album, .plex):
            return "x-rincon-cpcontainer:1004206c\(id)%3Aalbum?sid=212&amp;flags=8300&amp;sn=9"
        case (.artist, .plex):
            return "x-rincon-cpcontainer:1005004c\(id)%3Aartist?sid=212&amp;flags=8300&amp;sn=9"
        case (.playlist, .plex):
            return "x-rincon-cpcontainer:1006206c\(id)%3Aplaylist?sid=212&amp;flags=8300&amp;sn=9"
        case (.track, .tidal):
            return "track%2f\(id)"
        case (.album, .tidal):
            return "x-rincon-cpcontainer:1004206calbum%2f\(id)"
        case (.artist, .tidal):
            return ""
        case (.track, .unknown):
            return id.encodeProgramURI
        case (.radio, .tuneIn):
            return "x-sonosapi-stream:\(id)?sid=333&amp;flags=8232&amp;sn=14"
        case (.libraryPlaylist, .apple):
            return "x-rincon-cpcontainer:1006206clibraryplaylist%3a\(id)?sid=204&amp;flags=8300&amp;sn=4"
        default:
            assertionFailure("Failed")
            return ""
        }
    }

    public var alarmURIMetadata: String {
        return """
&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="" parentID="" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;\(containerClass)&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;\(content.service == .apple ? "SA_RINCON52231_X_#Svc52231-0-Token" : "SA_RINCON\(Self.spotifyLocal)_X_#Svc\(Self.spotifyLocal)-0-Token" )&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
    }

    public var URIMetadata: String {
        switch (content.type, content.service) {
        case (.track, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="00032020spotify%3atrack%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;\(Self.defaultSpotifyXMLNSFooter)
"""
        case (.album, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="1004206cspotify%3aalbum%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;\(Self.defaultSpotifyXMLNSFooter)
"""
        case (.playlist, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="1006206cspotify%3aplaylist%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;\(Self.defaultSpotifyXMLNSFooter)
"""
        case (.track, .apple):
            return """
\(Self.defaultXMLNSHeader) id="10032020song%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.libraryTrack, .apple):
            return """
\(Self.defaultXMLNSHeader) id="10032028librarytrack%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack.#TitleWithArtist&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.libraryAlbum, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1004206clibraryalbum%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum.#TitleWithArtist&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.libraryPlaylist, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1006206clibraryplaylist%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.album, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1004206calbum%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.playlist, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1006206cplaylist%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        case (.track, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="10036020\(id)%3Atrack"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.album, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;container parentID="" restricted="true" id="1004206c\(id)%3Aalbum"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/container&gt;&lt;/DIDL-Lite&gt;
"""
        case (.artist, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="1005004c\(id)%3Aartist"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.person.musicArtist&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.playlist, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="1006206c\(id)%3Aplaylist"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.track, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="00032020track%2f\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON44551_X_#Svc44551-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.album, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="00040000album%2f\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON44551_X_#Svc44551-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.artist, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="1005004c\(id)%3Aartist"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.person.musicArtist&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.track, .unknown):
            return """
\(Self.defaultXMLNSHeader) id="\(id.encodeProgramURI)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.radio, .tuneIn):
            return """
&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="-1" parentID="-1" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON85255_X_#Svc85255-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.favorite, _):
            return """
\(metadata?.URIMetadata ?? "")
"""
        default:
            return ""
        }
    }

    private static var defaultXMLNSHeader = """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item restricted="true"
"""
    private static var spotifyLocal = Locale.current.region?.identifier ?? "US" == "US" ? "3079" : "2311"

    private static var defaultSpotifyXMLNSFooter = """
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON\(spotifyLocal)_X_#Svc\(spotifyLocal)-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""

    private static var appleXMLNSFooter = """
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON52231_X_#Svc52231-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""

    public var containerClass: String {
        switch (content.type, content.service) {
        case (.track, .spotify):
            return "object.item.audioItem.musicTrack"
        case (.album, .spotify):
            return "object.container.album"
        case (.playlist, .spotify):
            return "object.container.playlistContainer"
        case (.track, .apple):
            return "object.item.audioItem.musicTrack"
        case (.album, .apple):
            return "object.container.album.musicAlbum.#AlbumView"
        case (.playlist, .apple):
            return "object.container.playlistContainer.#PlaylistView"
        case (.favorite, _):
            return "object.itemobject.item.sonos-favorite"
        case (.track, .library):
            return "object.item.audioItem.musicTrack"
        case (.album, .library):
            return "object.container.album"
        case (.playlist, .library):
            return "object.container.playlistContainer"
        default:
            return ""
        }
    }

    public var uriRadio: String? {
        switch (content.type, content.service) {
        case (.artist, .spotify):
            "x-sonosapi-radio:spotify%3aartistRadio%3a\(content.id)?sid=12&amp;flags=8300&amp;sn=1"
        case (.artist, .apple):
            "x-sonosapi-radio:radio%3ara.\(content.id)?sid=204&amp;flags=0&amp;sn=41"
        default:
            nil
        }
    }

    public var URIMetadataRadio: String? {
        switch (content.type, content.service) {
        case (.artist, .spotify):
            """
\(Self.defaultXMLNSHeader) id="100c206cspotify%3aartistRadio%3a\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast.#artistRadio&lt;/upnp:class&gt;\(Self.defaultSpotifyXMLNSFooter)
"""
        case (.artist, .apple):
            """
\(Self.defaultXMLNSHeader) id="000c0000radio%3ara.\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;\(Self.appleXMLNSFooter)
"""
        default:
            nil
        }
    }

    public static func == (lhs: PlayableContent, rhs: PlayableContent) -> Bool {
        lhs.content == rhs.content && lhs.title == rhs.title
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(content)
        hasher.combine(title)
    }
}

extension PlayableContent: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .playableContent)
        ProxyRepresentation(exporting: \.shareURL)
    }
}

extension UTType {
    public static var playableContent: UTType { UTType(exportedAs: "com.clic.playableContent") }
}


/// TODO: ADD
/// 
/// # In the overview below, the first columns indicates whether the class is (O)fficial of (E)xtended
//#
//#
//# O object                                                  -> <class 'soco.data_structures.DidlObject'>
//# O object.item                                             -> <class 'soco.data_structures.DidlItem'>
//# O object.item.audioItem                                   -> <class 'soco.data_structures.DidlAudioItem'>
//# O object.item.audioItem.musicTrack                        -> <class 'soco.data_structures.DidlMusicTrack'>
//# O object.item.audioItem.audioBook                         -> <class 'soco.data_structures.DidlAudioBook'>
//# O object.item.audioItem.audioBroadcast                    -> <class 'soco.data_structures.DidlAudioBroadcast'>
//# E object.item.audioItem.musicTrack.recentShow             -> <class 'soco.data_structures.DidlRecentShow'>
//# E object.item.audioItem.audioBroadcast.sonos-favorite     -> <class 'soco.data_structures.DidlAudioBroadcastFavorite'>
//# E object.itemobject.item.sonos-favorite                   -> <class 'soco.data_structures.DidlFavorite'>
//# O object.container                                        -> <class 'soco.data_structures.DidlContainer'>
//# O object.container.album                                  -> <class 'soco.data_structures.DidlAlbum'>
//# O object.container.album.musicAlbum                       -> <class 'soco.data_structures.DidlMusicAlbum'>
//# E object.container.album.musicAlbum.sonos-favorite        -> <class 'soco.data_structures.DidlMusicAlbumFavorite'>
//# E object.container.album.musicAlbum.compilation           -> <class 'soco.data_structures.DidlMusicAlbumCompilation'>
//# O object.container.person                                 -> <class 'soco.data_structures.DidlPerson'>
//# E object.container.person.composer                        -> <class 'soco.data_structures.DidlComposer'>
//# O object.container.person.musicArtist                     -> <class 'soco.data_structures.DidlMusicArtist'>
//# E object.container.albumlist                              -> <class 'soco.data_structures.DidlAlbumList'>
//# O object.container.playlistContainer                      -> <class 'soco.data_structures.DidlPlaylistContainer'>
//# E object.container.playlistContainer.sameArtist           -> <class 'soco.data_structures.DidlSameArtist'>
//# E object.container.playlistContainer.sonos-favorite       -> <class 'soco.data_structures.DidlPlaylistContainerFavorite'>
//# E object.container.playlistContainer.tracklist            -> <class 'soco.data_structures.DidlPlaylistContainerTracklist'>
//# O object.container.genre                                  -> <class 'soco.data_structures.DidlGenre'>
//# O object.container.genre.musicGenre                       -> <class 'soco.data_structures.DidlMusicGenre'>
//# E object.container.radioShow                              -> <class 'soco.data_structures.DidlRadioShow'>

//https://github.com/SoCo/SoCo/blob/51233a36bb47c52778151c4fcc96cc9e8631f28e/tests/official_and_extended_didl_classes.txt#L22
