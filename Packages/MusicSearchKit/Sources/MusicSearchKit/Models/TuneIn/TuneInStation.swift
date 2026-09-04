import Foundation

public struct TuneInStation: Sendable {
    public let title: String
    public let id: String
    public let currentTrack: String
    public let imageURL: URL?
    public let url: URL?
    public let stationInfo: Info?

    public struct Info: Sendable {
        public let name: String
        public let song: String?
        public let album: String?
        public let artist: String?
        public let location: URL?
    }
}
