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

        let tracks: [PlexTrack] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "track" }.flatMap { hub in
            hub["Track"].all.compactMap { track in
                guard
                    let title = track.element?.attribute(by: "title")?.text,
                    let artist = track.element?.attribute(by: "grandparentTitle")?.text,
                    let album = track.element?.attribute(by: "parentTitle")?.text,
                    let durationString = track.element?.attribute(by: "duration")?.text, let duration = Int(durationString),
                    let audioChannelsString = track["Media"].element?.attribute(by: "audioChannels")?.text, let audioChannels = Int(audioChannelsString),
                    let audioCodec = track["Media"].element?.attribute(by: "audioCodec")?.text,
                    let container = track["Media"].element?.attribute(by: "container")?.text,
                    let file = track["Media"]["Part"].element?.attribute(by: "file")?.text,
                    let parentThumbnail = track.element?.attribute(by: "parentThumb")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text,
                    let parentRatingKey = track.element?.attribute(by: "parentRatingKey")?.text,
                    let grandparentRatingKey = track.element?.attribute(by: "grandparentRatingKey")?.text,
                    let librarySectionID = track.element?.attribute(by: "librarySectionID")?.text
                else {
                    return nil
                }

                let imageURL = imageBase?.appending(path: parentThumbnail).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: accessToken)])

                return PlexTrack(
                    title: title,
                    artist: artist,
                    album: album,
                    duration: duration,
                    audioChannels: audioChannels,
                    audioCodec: audioCodec,
                    container: container,
                    file: file,
                    parentThumbnail: parentThumbnail,
                    ratingKey: ratingKey,
                    parentRatingKey: parentRatingKey,
                    grandparentRatingKey: grandparentRatingKey,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: Int(librarySectionID)
                )
            }
        }

        let albums: [PlexAlbum] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "album" }.flatMap { hub in
            hub["Directory"].all.compactMap { track in
                guard
                    let title = track.element?.attribute(by: "title")?.text,
                    let artist = track.element?.attribute(by: "parentTitle")?.text,
                    let year = track.element?.attribute(by: "year")?.text,
                    let thumb = track.element?.attribute(by: "thumb")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text,
                    let parentRatingKey = track.element?.attribute(by: "parentRatingKey")?.text,
                    let librarySectionID = track.element?.attribute(by: "librarySectionID")?.text
                else {
                    return nil
                }

                let art = track.element?.attribute(by: "art")?.text ?? ""
                let imageURL = imageBase?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: accessToken)])

                return PlexAlbum(
                    title: title,
                    artist: artist,
                    year: year,
                    thumb: thumb,
                    art: art,
                    ratingKey: ratingKey,
                    parentRatingKey: parentRatingKey,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: Int(librarySectionID),
                )
            }
        }

        let artists: [PlexArtist] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "artist" }.flatMap { hub in
            hub["Directory"].all.compactMap { track in
                guard
                    let name = track.element?.attribute(by: "title")?.text,
                    let ratingKey = track.element?.attribute(by: "ratingKey")?.text,
                    let thumb = track.element?.attribute(by: "thumb")?.text,
                    let librarySectionID = track.element?.attribute(by: "librarySectionID")?.text
                else {
                    return nil
                }

                let imageURL = imageBase?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: accessToken)])

                return PlexArtist(
                    name: name,
                    ratingKey: ratingKey,
                    imageURL: imageURL,
                    id: "\(id)%3A3%3A\(ratingKey)",
                    librarySectionID: Int(librarySectionID)
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

                let thumb = track.element?.attribute(by: "thumb")?.text ?? ""
                let imageURL = imageBase?.appending(path: thumb).appending(queryItems: [URLQueryItem(name: "X-Plex-Token", value: accessToken)])

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
