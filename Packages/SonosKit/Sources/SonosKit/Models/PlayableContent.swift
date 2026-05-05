import Foundation
import CoreTransferable
import UniformTypeIdentifiers
import Defaults

public struct PlayableContent: Equatable, Codable, Hashable, Identifiable, Sendable {
    public var id: String { content.id }
    public let title: String
    public let subtitle: String
    public let thumbnail: URL?
    public let artwork: URL?
    public let content: MediaContent
    public var previewURL: URL?
    public var metadata: PlayableContentMetadata?
    
    public var trackID: String { "\(content.id).\(metadata?.position?.description ?? "")" }
    
    public var radioID: String {
        id.replacingOccurrences(of: ".radio", with: "")
    }
    
    public init(
        title: String,
        subtitle: String,
        thumbnail: URL?,
        artwork: URL?,
        content: MediaContent,
        previewURL: URL? = nil,
        metadata: PlayableContentMetadata? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.thumbnail = thumbnail
        self.artwork = artwork
        self.content = content
        self.previewURL = previewURL
        self.metadata = metadata
    }
    
    public var shareURL: URL {
        // TODO: Check
#warning("DOULBE CHECK THIS")
        guard content.service != .unknown else { return URL(string: "clic://")! }
        guard let musicService = content.service.name?.lowercased() else { return  URL(string: "clic://")!  }
        return URL(string: "clic://play/\(musicService)/\(content.type)/\(id)")!
    }

    public var viewURL: URL {
        guard content.service != .unknown,
              let musicService = content.service.name?.lowercased() else {
            return URL(string: "clic://")!
        }
        return URL(string: "clic://view/\(musicService)/\(content.type)/\(id)")!
    }
    
    public var imageKey: String {
        if let albumID = metadata?.album, !albumID.isEmpty {
            let artist = metadata?.artist
            return [albumID, artist].compactMap { $0 }.joined(separator: ".")
        }
        return id
    }
    
    public var isPlayable: Bool { metadata?.isPlayable ?? true }
    
    public var uri: String {
        switch (content.type, content.service) {
        case (.track, .spotify):
            return "x-sonos-spotify:spotify%3atrack%3a\(id)?sid=12&amp;amp;sn=1"
        case (.album, .spotify):
            return "x-rincon-cpcontainer:1004206cspotify%3aalbum%3a\(id)?sid=12&amp;amp;sn=1"
        case (.playlist, .spotify):
            return "x-rincon-cpcontainer:1006206cspotify%3aplaylist%3a\(id)?sid=12&amp;amp;sn=1"
        case (.libraryTrack, .apple):
            return "x-sonos-http:librarytrack%3a\(id)?sid=204&amp;amp;sn=4"
        case (.libraryAlbum, .apple):
            return "x-rincon-cpcontainer:1004206clibraryalbum%3a\(id)?sid=204&amp;amp;sn=4"
        case (.track, .apple):
            return "x-sonos-http:song%3a\(id).mp4?sid=204&amp;amp;sn=4"
        case (.album, .apple):
            return "x-rincon-cpcontainer:1004206calbum%3a\(id)?sid=204&amp;amp;sn=4"
        case (.playlist, .apple):
            return "x-rincon-cpcontainer:1006206cplaylist%3a\(id)?sid=204&amp;amp;sn=4"
        case (.favorite, _):
            return id
        case (.folder, .library):
            return "x-rincon-playlist:RINCON_C43875EE4CCE01400#\(id)"
        case (_, .library):
            return id
        case (.track, .plex):
            return "x-sonosapi-hls-static:10036020\(id)%3Atrack?sid=212&amp;amp;sn=9"
        case (.album, .plex):
            return "x-rincon-cpcontainer:1004206c\(id)%3Aalbum?sid=212&amp;amp;sn=9"
        case (.artist, .plex):
            return "x-rincon-cpcontainer:1005004c\(id)%3Aartist?sid=212&amp;amp;sn=9"
        case (.playlist, .plex):
            return "x-rincon-cpcontainer:1006206c\(id)%3Aplaylist?sid=212&amp;flags=8300&amp;sn=9"
        case (.track, .tidal):
            return "track%2f\(id)?sid=174"
        case (.album, .tidal):
            return "x-rincon-cpcontainer:1004206calbum%2f\(id)?sid=174"
        case (.playlist, .tidal):
            return "x-rincon-cpcontainer:0006006cplaylist%2F\(id)?sid=174"
        case (.artist, .tidal):
            return ""
        case (_, .unknown):
            return id
        case (.radio, .tuneIn):
            return "x-sonosapi-stream:\(id)?sid=333&amp;flags=8232&amp;sn=14"
        case (.radio, .apple):
            return "x-sonosapi-radio:radio%3A\(id)?sid=204&amp;flags=32"
        case (.liveRadio, .apple):
            return "x-sonosapi-hls:hls%3A\(id)?sid=204&amp;flags=32"
        case (.libraryPlaylist, .apple):
            return "x-rincon-cpcontainer:1006206clibraryplaylist%3a\(id)?sid=204&amp;flags=8300&amp;sn=4"
        case (.track, .soundcloud):
            return "x-sonos-http:track-%3Esoundcloud%3Atracks%3A\(id)?sid=160&amp;flags=32"
        case (.playlist, .soundcloud):
            return "x-rincon-cpcontainer:0006006cplaylist-%3Esoundcloud%3Aplaylists%3A\(id)?sid=160&amp;amp;sn=23"
        case (.unique, _):
            return id
        default:
            assertionFailure("Failed")
            return ""
        }
    }
    
    public var alarmURIMetadata: String {
        return """
&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="" parentID="" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;\(containerClass)&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;\(content.service == .apple ? appleMusicServiceToken : spotifyMusicServiceToken)&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
    }
    
    public var URIMetadata: String {
        switch (content.type, content.service) {
        case (.track, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="00032020spotify%3atrack%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Spotify&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;
\(defaultSpotifyXMLNSFooter())
""".split(whereSeparator: \.isNewline).joined()
        case (.album, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="1004206cspotify%3aalbum%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Spotify&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;
\(defaultSpotifyXMLNSFooter())
"""
        case (.playlist, .spotify):
            return """
\(Self.defaultXMLNSHeader) id="1006206cspotify%3aplaylist%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Spotify&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;
\(defaultSpotifyXMLNSFooter())
"""
        case (.track, .apple):
            return """
\(Self.defaultXMLNSHeader) id="10032020song%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;
\(appleXMLNSFooter()))
""".split(whereSeparator: \.isNewline).joined()
            
        case (.libraryTrack, .apple):
            return """
\(Self.defaultXMLNSHeader) id="10032028librarytrack%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.item.audioItem.musicTrack.#TitleWithArtist&lt;/upnp:class&gt;
\(appleXMLNSFooter())
""".split(whereSeparator: \.isNewline).joined()
        case (.libraryAlbum, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1004206clibraryalbum%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.album.musicAlbum.#TitleWithArtist&lt;/upnp:class&gt;
\(appleXMLNSFooter())
"""
        case (.libraryPlaylist, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1006206clibraryplaylist%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;
\(appleXMLNSFooter())
"""
        case (.album, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1004206calbum%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;
\(appleXMLNSFooter())
"""
        case (.playlist, .apple):
            return """
\(Self.defaultXMLNSHeader) id="1006206cplaylist%3a\(id)" &gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;r:description&gt;Apple Music&lt;/r:description&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.playlistContainer.#PlaylistView&lt;/upnp:class&gt;
\(appleXMLNSFooter())
"""
        case (.track, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="10036020\(id)%3Atrack"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
""".split(whereSeparator: \.isNewline).joined()
        case (.album, .plex):
            return """
&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="0004006c\(id)%3Aalbum" parentID="(ignored)"
 restricted="true"&gt;
&lt;dc:title&gt;\(title)&lt;/dc:title&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-25ccc809-Token&lt;/desc&gt;
&lt;res&gt;x-rincon-cpcontainer:0004006\(id)8%3A3%3A2781%3Aalbum&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.artist, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="1005004c\(id)%3Aartist"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.person.musicArtist&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.playlist, .plex):
            return """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item parentID="" restricted="true" id="1006206c\(id)%3Aplaylist"&gt;
&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;
&lt;upnp:albumArtURI&gt;\(artwork?.absoluteString.ampersandSafe ?? "")&lt;/upnp:albumArtURI&gt;
&lt;upnp:class&gt;object.container.playlistContainer&lt;/upnp:class&gt;
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.track, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="00032020track%2f\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON44551_X_#Svc44551-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.album, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="00040000album%2f\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON44551_X_#Svc44551-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.playlist, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="0006006cplaylist%2F\(id)" &gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON44551_X_#Svc44551-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.artist, .tidal):
            return """
\(Self.defaultXMLNSHeader) id="1005004c\(id)%3Aartist"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.person.musicArtist&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON54279_X_#Svc54279-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case (.radio, .tuneIn):
            return """
&lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="-1" parentID="-1" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON85255_X_#Svc85255-0-Token&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
        case(.radio, .apple):
            return """
            &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="000c0020radio%3A\(id.encodeProgramURI)" parentID="(ignored)" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;\(appleMusicServiceToken)&lt;/desc&gt;&lt;res&gt;x-sonosapi-radio:radio%3A\(id.encodeProgramURI)?sid=204&amp;amp;flags=32&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
            """
        case(.liveRadio, .apple):
            return """
            &lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;00090120hls%3A\(id)&quot; parentID=&quot;(ignored)&quot; restricted=&quot;true&quot;&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;&lt;desc id=&quot;cdudn&quot; nameSpace=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot;&gt;\(appleMusicServiceToken)&lt;/desc&gt;&lt;res&gt;x-sonosapi-hls:hls%3A\(id)?sid=204&amp;amp;flags=32&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
            """
        case (.track, .soundcloud):
            return """
    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="00030020track-%3Esoundcloud%3Atracks%3A\(id)" parentID="(ignored)" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON40967_X_#Svc40967-7051ab01-Token&lt;/desc&gt;&lt;res&gt;x-sonos-http:track-%3Esoundcloud%3Atracks%3A\(id)?sid=160&amp;amp;flags=32&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
    """
        case (.playlist, .soundcloud):
            return """
    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="0006006cplaylist-%3Esoundcloud%3Aplaylists%3A\(id)" parentID="(ignored)" restricted="true"&gt;&lt;dc:title&gt;\(title.metaDataTitle)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON40967_X_#Svc40967-7051ab01-Token&lt;/desc&gt;&lt;res&gt;x-rincon-cpcontainer:0006006cplaylist-%3Esoundcloud%3Aplaylists%3A\(id)&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
    """
        case (_, .unknown):
            //            assertionFailure("Implement \(content.type)")
            return metadata?.URIMetadata ?? ""
        case (.album, .library):
            return """
    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="\(id.components(separatedBy: "#").last ?? "")" parentID="A:ALBUM" restricted="true"&gt;&lt;dc:title&gt;\(title)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;RINCON_AssociatedZPUDN&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
    """
        case (.track, .library):
            return """
    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="\(id.components(separatedBy: "#").last ?? "")" parentID="A:TRACKS" restricted="true"&gt;&lt;dc:title&gt;\(title)&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.musicTrack&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;RINCON_AssociatedZPUDN&lt;/desc&gt;&lt;res&gt;&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
    """
        case (.playlist, .library):
            return """
    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="\(id.components(separatedBy: "#").last ?? "")" parentID="SQ:" restricted="true"&gt;&lt;dc:title&gt;\(title)&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.playlistContainer&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;RINCON_AssociatedZPUDN&lt;/desc&gt;&lt;res&gt;\(id)&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
    """
        case (.unique, _):
            return metadata?.URIMetadata ?? ""
        default:
            return ""
        }
    }
    
    public var URIAndURIMetada: String {
    """
&lt;URIs&gt;
  &lt;URI uri=&quot;\(uri)&quot;&gt;
   \(URIMetadata)
  &lt;/URI&gt;
&lt;/URIs&gt;
"""
    }
    
    private static var defaultXMLNSHeader = """
&lt;DIDL-Lite xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/" xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;&lt;item restricted="true"
"""
    private var spotifyLocal: String {
        Locale.current.region?.identifier ?? "US" == "US" ? "3079" : "2311"
    }
    
    private var appleMusicServiceToken: String {
        if let storedTokenID = GroupStorageKeys.storage?.string(forKey: Defaults.GroupStorageKeys.appleMusicTokenID), !storedTokenID.isEmpty {
            return storedTokenID
        }
        return "SA_RINCON52231_X_#Svc52231-0-Token"
    }
    
    private var spotifyMusicServiceToken: String {
        if let storedTokenID = GroupStorageKeys.storage?.string(forKey: Defaults.GroupStorageKeys.spotifyMusicTokenID), !storedTokenID.isEmpty {
            return storedTokenID
        }
        return "SA_RINCON\(spotifyLocal)_X_#Svc\(spotifyLocal)-0-Token"
    }
    
    private func defaultSpotifyXMLNSFooter() -> String { """
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;\(spotifyMusicServiceToken)&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
    }

    private func appleXMLNSFooter() -> String { """
&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;\(appleMusicServiceToken)&lt;/desc&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
"""
}

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
        case (.folder, .library):
            return "object.container"
        default:
            return ""
        }
    }

    public var uriRadio: String? {
        switch (content.type, content.service) {
        case (.artist, .spotify), (.artistRadio, .spotify):
            "x-sonosapi-radio:spotify%3aartistRadio%3a\(radioID)?sid=12&amp;flags=8300&amp;sn=1"
        case (.artist, .apple), (.artistRadio, .apple):
            "x-sonosapi-radio:radio%3ara.\(radioID)?sid=204&amp;flags=0&amp;sn=41"
        case (.track, .spotify), (.songRadio, .spotify):
            "x-sonosapi-radio:spotify%3atrackRadio%3a\(radioID)?sid=12&amp;flags=0&amp;sn=1"
        case (.track, .apple), (.songRadio, .apple):
            "x-sonosapi-radio:radio%3Ara.\(radioID)?sid=204&amp;flags=32"
        default:
            nil
        }
    }

    public var URIMetadataRadio: String? {
        switch (content.type, content.service) {
        case (.artist, .spotify), (.artistRadio, .spotify):
            """
\(Self.defaultXMLNSHeader) id="100c206cspotify%3aartistRadio%3a\(radioID)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast.#artistRadio&lt;/upnp:class&gt;\(defaultSpotifyXMLNSFooter())
"""
        case (.artist, .apple), (.artistRadio, .apple):
            """
\(Self.defaultXMLNSHeader) id="000c0000radio%3ara.\(radioID)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;\(appleXMLNSFooter())
"""
        case (.track, .spotify), (.songRadio, .spotify):
            """
\(Self.defaultXMLNSHeader) id="000c0000spotify%3atrackRadio%3a\(radioID)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;\(defaultSpotifyXMLNSFooter())
"""
        case (.track, .apple), (.songRadio, .apple):
            """
\(Self.defaultXMLNSHeader) id="000c0020radio%3ara.\(radioID)" &gt;&lt;dc:title&gt;\(title.metaDataTitle) Radio&lt;/dc:title&gt;&lt;upnp:class&gt;object.item.audioItem.audioBroadcast&lt;/upnp:class&gt;\(appleXMLNSFooter())
"""
        default:
            nil
        }
    }

    public static func == (lhs: PlayableContent, rhs: PlayableContent) -> Bool {
        lhs.content == rhs.content && lhs.title == rhs.title && lhs.metadata?.position ?? 0 == rhs.metadata?.position ?? 0
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(content)
        hasher.combine(title)
        hasher.combine(metadata?.position ?? 0)
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

extension PlayableContent {
    public var isSonosPlaylist: Bool {
        content.type == .playlist && content.service == .library
    }
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
