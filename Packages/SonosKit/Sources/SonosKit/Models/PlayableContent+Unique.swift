public extension PlayableContent {
    static var soundCloudLikes: Self {
        .init(
            title: "Likes",
            subtitle: "SoundCloud Likes",
            thumbnail: nil,
            artwork: nil,
            content: .init(service: .soundcloud, id: "x-rincon-cpcontainer:0006006clikes", type: .unique, location: nil),
            previewURL: nil,
            metadata: .init(
                URIMetadata: """
                    &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="0006006clikes" parentID="(ignored)" restricted="true"&gt;&lt;dc:title&gt;Likes&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON40967_X_#Svc40967-7051ab01-Token&lt;/desc&gt;&lt;res&gt;x-rincon-cpcontainer:0006006clikes&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
                    """
            )
        )
    }
    
    static var spotifyLikes: Self {
        .init(
            title: "Likes",
            subtitle: "Spotify Likes",
            thumbnail: nil,
            artwork: nil,
            content: .init(service: .spotify, id: "x-rincon-cpcontainer:000e006cyour_songs", type: .unique, location: nil),
            previewURL: nil,
            metadata: .init(
                URIMetadata: """
                        &lt;DIDL-Lite xmlns:dc="http://purl.org/dc/elements/1.1/" xmlns:upnp="urn:schemas-upnp-org:metadata-1-0/upnp/" xmlns:r="urn:schemas-rinconnetworks-com:metadata-1-0/" xmlns="urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/"&gt;&lt;item id="000e006cyour_songs" parentID="(ignored)" restricted="true"&gt;&lt;dc:title&gt;Songs&lt;/dc:title&gt;&lt;upnp:class&gt;object.container.album.musicAlbum&lt;/upnp:class&gt;&lt;desc id="cdudn" nameSpace="urn:schemas-rinconnetworks-com:metadata-1-0/"&gt;SA_RINCON3079_X_#Svc3079-0-Token&lt;/desc&gt;&lt;res&gt;x-rincon-cpcontainer:000e006cyour_songs&lt;/res&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;
                        """
            )
        )
    }
}
