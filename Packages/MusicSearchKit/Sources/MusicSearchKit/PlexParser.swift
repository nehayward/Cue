import Foundation
import SWXMLHash

public final class PlexParser {
    /// - Parameter baseURL: The connection actually used to fetch the data
    ///   (e.g. the resolved LAN connection under `.auto`). Image URLs are built
    ///   against it so artwork loads over the same connection as the results;
    ///   falls back to the preference-based URL when nil.
    func parseXML(xmlData: Data, plexServer: PlexServer, connectionPreference: PlexAPI.ConnectionPreference = .nonLocal, baseURL: URL? = nil) -> PlexResults? {
        let xml = XMLHash.parse(xmlData)
        guard let accessToken = plexServer.accessToken, let id = plexServer.clientIdentifier else { return nil }
        let imageBase = baseURL ?? plexServer.baseURL(preferring: connectionPreference)

        // Token-signed URL for a server path on the connection the results
        // came over: artwork, and a track's media part.
        func signedURL(for path: String?) -> URL? {
            path.flatMap {
                imageBase?.appending(path: $0).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: accessToken)])
            }
        }
        // Token-signed image URL for a thumb path; one place to change how
        // Plex artwork is authenticated/transcoded.
        func imageURL(for thumb: String?) -> URL? {
            signedURL(for: thumb)
        }

        let tracks: [PlexTrack] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "track" }.flatMap { hub in
            hub["Track"].all.compactMap { track in
                // Only the title and ratingKey are essential (the Sonos URI is
                // built from the ratingKey). Everything else is detail that
                // servers may omit from hub search results — requiring all of
                // it dropped entire libraries' songs from search.
                guard
                    let title = track.element?.attribute(by: "title")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text
                else {
                    return nil
                }

                let thumb = track.element?.attribute(by: "parentThumb")?.text
                    ?? track.element?.attribute(by: "thumb")?.text
                let imageURL = imageURL(for: thumb)
                let userRating = (track.element?.attribute(by: "userRating")?.text).flatMap(Double.init)

                return PlexTrack(
                    title: title,
                    artist: track.element?.attribute(by: "grandparentTitle")?.text ?? "",
                    album: track.element?.attribute(by: "parentTitle")?.text ?? "",
                    duration: (track.element?.attribute(by: "duration")?.text).flatMap(Int.init),
                    audioChannels: (track["Media"].element?.attribute(by: "audioChannels")?.text).flatMap(Int.init),
                    audioCodec: track["Media"].element?.attribute(by: "audioCodec")?.text,
                    bitrate: (track["Media"].element?.attribute(by: "bitrate")?.text).flatMap(Int.init),
                    container: track["Media"].element?.attribute(by: "container")?.text,
                    file: track["Media"]["Part"].element?.attribute(by: "file")?.text,
                    parentThumbnail: thumb,
                    ratingKey: ratingKey,
                    parentRatingKey: track.element?.attribute(by: "parentRatingKey")?.text,
                    grandparentRatingKey: track.element?.attribute(by: "grandparentRatingKey")?.text,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: (track.element?.attribute(by: "librarySectionID")?.text).flatMap(Int.init),
                    userRating: userRating,
                    // The Part's key, signed the way library rows are. Without
                    // it a song from search had nothing for this device to
                    // play: the player turned it away as unplayable.
                    streamURL: signedURL(for: track["Media"]["Part"].element?.attribute(by: "key")?.text)
                )
            }
        }

        let albums: [PlexAlbum] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "album" }.flatMap { hub in
            hub["Directory"].all.compactMap { track in
                guard
                    let title = track.element?.attribute(by: "title")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text
                else {
                    return nil
                }

                let thumb = track.element?.attribute(by: "thumb")?.text
                let art = track.element?.attribute(by: "art")?.text ?? ""
                let imageURL = imageURL(for: thumb)
                let userRating = (track.element?.attribute(by: "userRating")?.text).flatMap(Double.init)

                return PlexAlbum(
                    title: title,
                    artist: track.element?.attribute(by: "parentTitle")?.text ?? "",
                    year: track.element?.attribute(by: "year")?.text ?? "",
                    thumb: thumb,
                    art: art,
                    ratingKey: ratingKey,
                    parentRatingKey: track.element?.attribute(by: "parentRatingKey")?.text,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: (track.element?.attribute(by: "librarySectionID")?.text).flatMap(Int.init),
                    userRating: userRating,
                    leafCount: (track.element?.attribute(by: "leafCount")?.text).flatMap(Int.init)
                )
            }
        }

        let artists: [PlexArtist] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "artist" }.flatMap { hub in
            hub["Directory"].all.compactMap { track in
                guard
                    let name = track.element?.attribute(by: "title")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text
                else {
                    return nil
                }

                let thumb = track.element?.attribute(by: "thumb")?.text
                let imageURL = imageURL(for: thumb)

                return PlexArtist(
                    name: name,
                    ratingKey: ratingKey,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: (track.element?.attribute(by: "librarySectionID")?.text).flatMap(Int.init)
                )
            }
        }

        let playlists: [PlexPlaylist] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "playlist" }.flatMap { hub in
            hub["Playlist"].all.compactMap { track in
                guard
                    let title = track.element?.attribute(by: "title")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text
                else {
                    return nil
                }

                let imageURL = imageURL(for: track.element?.attribute(by: "thumb")?.text ?? "")

                return PlexPlaylist(
                    title: title,
                    ratingKey: ratingKey,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)"
                )
            }
        }

        return PlexResults(tracks: tracks, album: albums, artists: artists, playlists: playlists)
    }
}
