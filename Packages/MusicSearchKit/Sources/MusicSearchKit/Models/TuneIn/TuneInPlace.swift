import Foundation

/// Where a station is, from its description (`Describe.ashx`): the point
/// TuneIn pins it at, when it has one, and the place it names ("Seattle,
/// WA"), which can be looked up on a map when it doesn't.
public struct TuneInPlace: Codable, Hashable, Sendable {
    public var latitude: Double?
    public var longitude: Double?
    public var location: String?

    public init(latitude: Double? = nil, longitude: Double? = nil, location: String? = nil) {
        self.latitude = latitude
        self.longitude = longitude
        self.location = location
    }

    /// Both halves of the point, or nil when TuneIn gave none.
    public var coordinate: (latitude: Double, longitude: Double)? {
        guard let latitude, let longitude else { return nil }
        return (latitude, longitude)
    }

    /// TuneIn's `latlon`, "47.6062,-122.3321". Any run of characters that
    /// can't be in a number separates the two, so a space or a semicolon
    /// reads the same. Nil unless it is exactly two numbers that make a
    /// point on Earth, and not 0,0, which is where a missing point lands.
    static func coordinate(fromLatLon text: String) -> (latitude: Double, longitude: Double)? {
        let numbers = text
            .split { !"0123456789.-+".contains($0) }
            .compactMap { Double($0) }
        guard numbers.count == 2 else { return nil }
        var (latitude, longitude) = (numbers[0], numbers[1])
        // A pair the wrong way round still names one point: a latitude
        // can't pass 90.
        if abs(latitude) > 90, abs(longitude) <= 90 {
            swap(&latitude, &longitude)
        }
        guard abs(latitude) <= 90, abs(longitude) <= 180,
              latitude != 0 || longitude != 0 else { return nil }
        return (latitude, longitude)
    }
}
