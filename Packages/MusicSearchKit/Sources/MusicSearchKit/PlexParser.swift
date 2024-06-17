import Foundation
import SWXMLHash

public final class PlexParser {
    func parseXML(xmlData: Data, baseURL: URL? = nil, clientID: String = "baff30cefb83c207ba740a1f7d11620e21833bf8") -> PlexResults? {
        let xml = XMLHash.parse(xmlData)

        // Parse tracks
        let tracks: [PlexTrack] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "track" }.flatMap { hub in
            hub["Track"].all.map { track in
                PlexTrack(
                    title: track.element!.attribute(by: "title")!.text,
                    artist: track.element!.attribute(by: "grandparentTitle")!.text,
                    duration: Int(track.element!.attribute(by: "duration")!.text)!,
                    audioChannels: Int(track["Media"].element!.attribute(by: "audioChannels")!.text)!,
                    audioCodec: track["Media"].element!.attribute(by: "audioCodec")!.text,
                    container: track["Media"].element!.attribute(by: "container")!.text,
                    file: track["Media"]["Part"].element!.attribute(by: "file")!.text,
                    parentThumbnail: track.element!.attribute(by: "parentThumb")!.text,
                    ratingKey: track.element!.attribute(by: "ratingKey")!.text,
                    imageURL: baseURL?.appending(path: track.element!.attribute(by: "parentThumb")!.text),
                    id: "\(clientID)%3A3%3A\(track.element!.attribute(by: "ratingKey")!.text)"
                )
            }
        }

        let albums: [PlexAlbum] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "album" }.flatMap { hub in
            hub["Directory"].all.map { track in
                PlexAlbum(
                    title: track.element!.attribute(by: "title")!.text,
                    artist: track.element!.attribute(by: "parentTitle")!.text,
                    year: track.element!.attribute(by: "year")!.text,
                    thumb: track.element!.attribute(by: "thumb")!.text,
                    art: track.element!.attribute(by: "art")?.text ?? "",
                    ratingKey: track.element!.attribute(by: "ratingKey")!.text,
                    imageURL: baseURL?.appending(path: track.element!.attribute(by: "thumb")!.text),
                    id: "\(clientID)%3A3%3A\(track.element!.attribute(by: "ratingKey")!.text)"
                )
            }
        }

        let artists: [PlexArtist] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "artist" }.flatMap { hub in
            hub["Directory"].all.map { track in
                PlexArtist(
                    name: track.element!.attribute(by: "title")!.text,
                    ratingKey: track.element!.attribute(by: "ratingKey")!.text,
                    imageURL: baseURL?.appending(path: track.element!.attribute(by: "thumb")!.text),
                    id: "\(clientID)%3A3%3A\(track.element!.attribute(by: "ratingKey")!.text)"
                )
            }
        }

        let playlists: [PlexPlaylist] = xml["MediaContainer"]["Hub"].all.filter { $0.element?.attribute(by: "type")?.text == "playlist" }.flatMap { hub in
            hub["Playlist"].all.map { track in
                PlexPlaylist(
                    title: track.element!.attribute(by: "title")!.text,
                    ratingKey: track.element!.attribute(by: "ratingKey")!.text,
                    imageURL: baseURL?.appending(path: track.element?.attribute(by: "thumb")?.text ?? ""),
                    id: "\(clientID)%3A3%3A\(track.element!.attribute(by: "ratingKey")!.text)"
                )
            }
        }

        return PlexResults(tracks: tracks, album: albums, artists: artists, playlists: playlists)
    }

}
