import XCTest
@testable import SonosKit

final class FavoritesParserTests: XCTestCase {

    /// A Music Library favorite's cover is a path on the speaker, which only
    /// loads with the speaker in front of it.
    func testMusicLibraryCoverIsAskedOfTheSpeaker() {
        let url = FavoritesParser.artworkURL("/getaa?s=1&u=x-file-cifs%3a%2f%2fnas%2fmusic%2f01.flac&v=12", speakerIP: "192.168.1.10")
        XCTAssertEqual(url?.absoluteString, "http://192.168.1.10:1400/getaa?s=1&u=x-file-cifs%3a%2f%2fnas%2fmusic%2f01.flac&v=12")
    }

    func testWholeAddressesAreLeftAlone() {
        let spotify = "https://i.scdn.co/image/ab67616d0000b273abc"
        XCTAssertEqual(FavoritesParser.artworkURL(spotify, speakerIP: "192.168.1.10")?.absoluteString, spotify)
        let speaker = "http://192.168.1.20:1400/getaa?s=1&u=x"
        XCTAssertEqual(FavoritesParser.artworkURL(speaker, speakerIP: "192.168.1.10")?.absoluteString, speaker)
    }

    func testNoCover() {
        XCTAssertNil(FavoritesParser.artworkURL("", speakerIP: "192.168.1.10"))
        XCTAssertNil(FavoritesParser.artworkURL("  \n", speakerIP: "192.168.1.10"))
    }

    /// The whole `Browse FV:2` answer, a Music Library album beside a
    /// streaming one, as the speaker sends it: the DIDL escaped once into
    /// `Result`, each item's own metadata (`r:resMD`) escaped twice.
    func testParsesCoversFromABrowseResponse() throws {
        let favorites = FavoritesParser(IP: "192.168.1.10").parse(xml: Self.browseResponse)
        XCTAssertEqual(favorites.map(\.title), ["Abbey Road", "Discovery"])

        let library = try XCTUnwrap(favorites.first)
        XCTAssertEqual(library.subtitle, "Music Library")
        XCTAssertEqual(
            library.thumbnail?.absoluteString,
            "http://192.168.1.10:1400/getaa?s=1&u=x-file-cifs%3a%2f%2fnas%2fmusic%2fBeatles%2f01.flac&v=12"
        )
        XCTAssertEqual(library.artwork, library.thumbnail)

        let streaming = try XCTUnwrap(favorites.last)
        XCTAssertEqual(streaming.thumbnail?.absoluteString, "https://i.scdn.co/image/ab67616d0000b273abc")
    }

    private static let browseResponse = """
    <s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/"><s:Body><u:BrowseResponse xmlns:u="urn:schemas-upnp-org:service:ContentDirectory:1"><Result>\
    &lt;DIDL-Lite xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot; xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot; xmlns:r=&quot;urn:schemas-rinconnetworks-com:metadata-1-0/&quot; xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;\
    &lt;item id=&quot;FV:2/12&quot; parentID=&quot;FV:2&quot; restricted=&quot;false&quot;&gt;\
    &lt;dc:title&gt;Abbey Road&lt;/dc:title&gt;\
    &lt;upnp:class&gt;object.itemobject.item.sonos-favorite&lt;/upnp:class&gt;\
    &lt;r:ordinal&gt;0&lt;/r:ordinal&gt;\
    &lt;res protocolInfo=&quot;x-rincon-playlist:*:*:*&quot;&gt;x-rincon-playlist:RINCON_000E58000000001400#A:ALBUM/Abbey%20Road&lt;/res&gt;\
    &lt;upnp:albumArtURI&gt;/getaa?s=1&amp;amp;u=x-file-cifs%3a%2f%2fnas%2fmusic%2fBeatles%2f01.flac&amp;amp;v=12&lt;/upnp:albumArtURI&gt;\
    &lt;r:type&gt;instantPlay&lt;/r:type&gt;\
    &lt;r:description&gt;Music Library&lt;/r:description&gt;\
    &lt;r:resMD&gt;&amp;lt;DIDL-Lite xmlns:dc=&amp;quot;http://purl.org/dc/elements/1.1/&amp;quot; xmlns:upnp=&amp;quot;urn:schemas-upnp-org:metadata-1-0/upnp/&amp;quot; xmlns:r=&amp;quot;urn:schemas-rinconnetworks-com:metadata-1-0/&amp;quot; xmlns=&amp;quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&amp;quot;&amp;gt;&amp;lt;item id=&amp;quot;A:ALBUM/Abbey%20Road&amp;quot; parentID=&amp;quot;A:ALBUM&amp;quot; restricted=&amp;quot;true&amp;quot;&amp;gt;&amp;lt;dc:title&amp;gt;Abbey Road&amp;lt;/dc:title&amp;gt;&amp;lt;upnp:class&amp;gt;object.container.album.musicAlbum&amp;lt;/upnp:class&amp;gt;&amp;lt;desc id=&amp;quot;cdudn&amp;quot; nameSpace=&amp;quot;urn:schemas-rinconnetworks-com:metadata-1-0/&amp;quot;&amp;gt;RINCON_AssociatedZPUDN&amp;lt;/desc&amp;gt;&amp;lt;/item&amp;gt;&amp;lt;/DIDL-Lite&amp;gt;&lt;/r:resMD&gt;\
    &lt;/item&gt;\
    &lt;item id=&quot;FV:2/13&quot; parentID=&quot;FV:2&quot; restricted=&quot;false&quot;&gt;\
    &lt;dc:title&gt;Discovery&lt;/dc:title&gt;\
    &lt;upnp:class&gt;object.itemobject.item.sonos-favorite&lt;/upnp:class&gt;\
    &lt;r:ordinal&gt;1&lt;/r:ordinal&gt;\
    &lt;res protocolInfo=&quot;x-rincon-cpcontainer:*:*:*&quot;&gt;x-rincon-cpcontainer:1004206calbum%3a2noRn2Aes5aoNVsU6iWThc?sid=12&amp;amp;flags=8300&amp;amp;sn=1&lt;/res&gt;\
    &lt;upnp:albumArtURI&gt;https://i.scdn.co/image/ab67616d0000b273abc&lt;/upnp:albumArtURI&gt;\
    &lt;r:type&gt;instantPlay&lt;/r:type&gt;\
    &lt;r:description&gt;Spotify&lt;/r:description&gt;\
    &lt;r:resMD&gt;&amp;lt;DIDL-Lite xmlns:dc=&amp;quot;http://purl.org/dc/elements/1.1/&amp;quot; xmlns:upnp=&amp;quot;urn:schemas-upnp-org:metadata-1-0/upnp/&amp;quot; xmlns:r=&amp;quot;urn:schemas-rinconnetworks-com:metadata-1-0/&amp;quot; xmlns=&amp;quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&amp;quot;&amp;gt;&amp;lt;item id=&amp;quot;1004206calbum%3a2noRn2Aes5aoNVsU6iWThc&amp;quot; parentID=&amp;quot;&amp;quot; restricted=&amp;quot;true&amp;quot;&amp;gt;&amp;lt;dc:title&amp;gt;Discovery&amp;lt;/dc:title&amp;gt;&amp;lt;upnp:class&amp;gt;object.container.album.musicAlbum&amp;lt;/upnp:class&amp;gt;&amp;lt;desc id=&amp;quot;cdudn&amp;quot; nameSpace=&amp;quot;urn:schemas-rinconnetworks-com:metadata-1-0/&amp;quot;&amp;gt;SA_RINCON3079_X_#Svc3079-0-Token&amp;lt;/desc&amp;gt;&amp;lt;/item&amp;gt;&amp;lt;/DIDL-Lite&amp;gt;&lt;/r:resMD&gt;\
    &lt;/item&gt;\
    &lt;/DIDL-Lite&gt;\
    </Result><NumberReturned>2</NumberReturned><TotalMatches>2</TotalMatches><UpdateID>7</UpdateID></u:BrowseResponse></s:Body></s:Envelope>
    """
}
