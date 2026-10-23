import MapKit
import MusicSearchKit
import OSLog
import SonosKit
import SwiftUI

/// Where the Radio tab's stations are, for its map. TuneIn's browse pages
/// carry no place, so each station's description (`Describe.ashx`) is
/// asked once, a few at a time, and what it says is kept on disk: a
/// station doesn't move. A description with a place name but no point
/// ("Seattle, WA") is looked up with MapKit; one naming only a country
/// ("US") isn't placed. Search This Area adds the
/// stations TuneIn counts as local to another point, for the rest of the
/// session.
@MainActor
@Observable
final class RadioMap {
    static let shared = RadioMap()

    /// What's known of where each station is, by station id.
    private(set) var places: [String: Place] = [:]
    /// Stations Search This Area found, each once, so the map fills in as
    /// it's explored.
    private(set) var explored: [PlayableContent] = []
    /// Every area searched, latest last.
    private(set) var searches: [AreaSearch] = []
    /// Descriptions asked for and not yet back.
    private(set) var pendingCount = 0
    private(set) var isSearchingArea = false

    var isLocating: Bool { pendingCount > 0 }

    struct Place: Codable, Hashable {
        var latitude: Double?
        var longitude: Double?
        var location: String?
        /// When TuneIn was asked. A station it placed nowhere is asked
        /// again after `recheckInterval`.
        var checked: Date
    }

    /// What's kept on disk. A file of another version is ignored, and the
    /// next save writes over it, so every station is asked again.
    private struct Store: Codable {
        /// Up by one whenever what's kept changes. 2: stations named only
        /// by a country no longer pinned at its middle, and markets
        /// ("Seattle-Tacoma, WA") placed at their first city. Before it,
        /// the file was the places alone.
        static let currentVersion = 2

        var version = Store.currentVersion
        var places: [String: Place]
    }

    struct AreaSearch: Equatable {
        let latitude: Double
        let longitude: Double
        let stations: [PlayableContent]

        var center: CLLocation { CLLocation(latitude: latitude, longitude: longitude) }
    }

    private struct Point: Hashable {
        let latitude: Double
        let longitude: Double
    }

    /// Descriptions asked for at once. TuneIn answers a burst with 403s.
    private static let concurrentLookups = 4
    private static let recheckInterval: TimeInterval = 7 * 24 * 60 * 60
    private static let storeURL = URL.cachesDirectory.appending(path: "RadioMapPlaces.json")
    private static let log = Logger(subsystem: "dance.cue", category: "radioMap")

    /// How often answers reach `places`. Each change there redraws every
    /// view reading the map, so a burst of answers lands as one.
    private static let publishInterval: Duration = .milliseconds(500)

    @ObservationIgnored private var inFlight: Set<String> = []
    /// Answers back but not yet in `places`, by station id: the place to
    /// keep, or nil for nothing to keep (ask again next time).
    @ObservationIgnored private var unpublished: [String: Place?] = [:]
    @ObservationIgnored private var publishTask: Task<Void, Never>?
    /// Place names already looked up, misses included, so a city's
    /// stations cost one lookup between them.
    @ObservationIgnored private var geocoded: [String: Point?] = [:]
    @ObservationIgnored private var storeLoad: Task<Void, Never>?
    @ObservationIgnored private var lastSave: Task<Void, Never>?

    private init() {}

    // MARK: - Stations

    /// The stations of `list` that have a point, each once, in its order.
    func mapped(_ list: [PlayableContent]) -> [RadioMapStation] {
        var seen = Set<String>()
        return list.compactMap { station in
            guard seen.insert(station.id).inserted,
                  let place = places[station.id],
                  let latitude = place.latitude,
                  let longitude = place.longitude else { return nil }
            return RadioMapStation(station: station, latitude: latitude, longitude: longitude, location: place.location)
        }
    }

    /// Looks up where each of `stations` is that the map doesn't know yet.
    /// Only TuneIn's stations have a description to ask. Stations land on
    /// the map one by one as their answers come back.
    func locate(_ stations: [PlayableContent]) async {
        await loadStore()

        var seen = Set<String>()
        let ids = stations.compactMap { station -> String? in
            guard station.content.service == .tuneIn,
                  seen.insert(station.id).inserted,
                  !inFlight.contains(station.id),
                  needsLookup(station.id) else { return nil }
            return station.id
        }
        guard !ids.isEmpty else { return }
        inFlight.formUnion(ids)
        pendingCount += ids.count
        Self.log.debug("locating \(ids.count) stations")

        // Unstructured, so the lookups outlive the view task that asked:
        // pushing the map from its tile ends the Radio tab's task, and the
        // map's own `locate` skips what's in flight.
        await Task {
            await lookUp(ids)
        }.value
    }

    private func lookUp(_ ids: [String]) async {
        let tuneIn = TuneInBrowseService.shared
        var tally = Tally()
        await withTaskGroup(of: (String, TuneInPlace?).self) { group in
            var next = 0
            while next < min(Self.concurrentLookups, ids.count) {
                let id = ids[next]
                next += 1
                group.addTask { (id, await tuneIn.place(for: id)) }
            }
            while let (id, place) = await group.next() {
                // The next lookup goes out before this answer is kept, so a
                // place name being geocoded doesn't hold TuneIn up.
                if next < ids.count {
                    let nextID = ids[next]
                    next += 1
                    group.addTask { (nextID, await tuneIn.place(for: nextID)) }
                }
                tally.count(await record(place, for: id))
            }
        }
        publish()
        save()
        // How the run went, for a device's console
        // (`CUE_LOG_FILTER=radioMap`): many without an answer is TuneIn
        // turning the lookups away; many with no place is stations it
        // doesn't place.
        Self.log.notice("placed \(tally.placed) of \(ids.count): \(tally.nowhere) with no place, \(tally.unanswered) without an answer")
    }

    /// What became of each lookup in a run.
    private struct Tally {
        var placed = 0
        var nowhere = 0
        var unanswered = 0

        /// `kept` is what `record` kept: nil for no answer.
        mutating func count(_ kept: Place?) {
            guard let kept else {
                unanswered += 1
                return
            }
            if kept.latitude != nil {
                placed += 1
            } else {
                nowhere += 1
            }
        }
    }

    /// Asks TuneIn for the stations local to a point and puts them on the
    /// map with the rest.
    ///
    /// Searching until the stations found are placed, not just listed: in
    /// between, the search would read as one that placed nothing, and "No
    /// Stations Found Here" flashed up before they landed.
    func searchArea(latitude: Double, longitude: Double) async {
        isSearchingArea = true
        defer { isSearchingArea = false }
        let found = await TuneInBrowseService.shared.stations(nearLatitude: latitude, longitude: longitude)

        let known = Set(explored.map(\.id))
        explored.append(contentsOf: found.filter { !known.contains($0.id) })
        searches.append(AreaSearch(latitude: latitude, longitude: longitude, stations: found))
        Self.log.notice("area search at \(latitude, format: .fixed(precision: 3)),\(longitude, format: .fixed(precision: 3)) found \(found.count) stations")
        await locate(found)
    }

    private func needsLookup(_ id: String) -> Bool {
        guard let place = places[id] else { return true }
        return place.latitude == nil && place.checked.distance(to: .now) > Self.recheckInterval
    }

    /// Keeps what a description said, for the next `publish`. No answer
    /// at all (offline, turned away, or a place name the map couldn't be
    /// asked about) keeps nothing, so the station is asked again next time.
    /// Returns what it kept, for the run's tally.
    private func record(_ found: TuneInPlace?, for id: String) async -> Place? {
        let kept = await self.place(from: found)
        unpublished.updateValue(kept, forKey: id)
        publishSoon()
        return kept
    }

    private func place(from found: TuneInPlace?) async -> Place? {
        guard let found else { return nil }
        var place = Place(latitude: found.latitude, longitude: found.longitude, location: found.location, checked: .now)
        if found.coordinate == nil, let location = found.location {
            switch await geocode(location) {
            case let .found(point):
                place.latitude = point.latitude
                place.longitude = point.longitude
            case .nowhere:
                break
            case .failed:
                return nil
            }
        }
        return place
    }

    private func publishSoon() {
        guard publishTask == nil else { return }
        publishTask = Task {
            try? await Task.sleep(for: Self.publishInterval)
            // Cancelled: a `publish` already came, and took these answers.
            guard !Task.isCancelled else { return }
            publish()
        }
    }

    /// Puts every answer back since the last time into `places` in one
    /// change. A station stays in flight until then, so a `locate` in the
    /// meantime doesn't ask for it again.
    private func publish() {
        publishTask?.cancel()
        publishTask = nil
        guard !unpublished.isEmpty else { return }
        let answers = unpublished
        unpublished = [:]

        var updated = places
        for (id, place) in answers {
            if let place {
                updated[id] = place
            }
            inFlight.remove(id)
        }
        places = updated
        pendingCount -= answers.count
    }

    private enum Geocoded {
        case found(Point)
        /// The map knows no such place.
        case nowhere
        /// Offline, throttled, or no geocoder on this system: ask again.
        case failed
    }

    /// Where a place TuneIn names is, trying each of its names in turn
    /// (`TuneInPlace.mapQueries`): "Seattle-Tacoma, WA", then "Seattle, WA".
    private func geocode(_ location: String) async -> Geocoded {
        if let known = geocoded[location] {
            return known.map(Geocoded.found) ?? .nowhere
        }
        var failed = false
        for query in TuneInPlace.mapQueries(for: location) {
            switch await geocodeQuery(query) {
            case let .found(point):
                geocoded[location] = point
                return .found(point)
            case .nowhere:
                continue
            case .failed:
                failed = true
            }
        }
        // Only a real answer is kept, found or not.
        guard !failed else { return .failed }
        geocoded[location] = .some(nil)
        return .nowhere
    }

    private func geocodeQuery(_ query: String) async -> Geocoded {
        guard #available(iOS 26.0, macOS 26.0, visionOS 26.0, *),
              let request = MKGeocodingRequest(addressString: query) else { return .failed }
        do {
            let point = try await request.mapItems.first.map { item in
                Point(latitude: item.location.coordinate.latitude, longitude: item.location.coordinate.longitude)
            }
            return point.map(Geocoded.found) ?? .nowhere
        } catch let error as MKError where error.code == .placemarkNotFound {
            return .nowhere
        } catch {
            Self.log.debug("geocoding failed: \(error.localizedDescription, privacy: .public)")
            return .failed
        }
    }

    // MARK: - Store

    private func loadStore() async {
        if storeLoad == nil {
            let url = Self.storeURL
            storeLoad = Task {
                let stored = await Task.detached(priority: .utility) { () -> [String: Place]? in
                    guard let data = try? Data(contentsOf: url),
                          let store = try? JSONDecoder().decode(Store.self, from: data),
                          store.version == Store.currentVersion else { return nil }
                    return store.places
                }.value
                if let stored {
                    // Anything looked up while the file was read is newer.
                    places.merge(stored) { current, _ in current }
                }
            }
        }
        await storeLoad?.value
    }

    /// Writes the places off the main actor, each write after the last so
    /// an older one never lands on top.
    private func save() {
        let snapshot = places
        let url = Self.storeURL
        let previous = lastSave
        lastSave = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(Store(places: snapshot)) else { return }
            try? data.write(to: url, options: .atomic)
        }
    }

    // MARK: - Framing

    /// The stations around the middle of `stations`. TuneIn's local page
    /// carries the odd network from far away, which would zoom the map out
    /// to a whole country.
    static func core(of stations: [RadioMapStation], radius: CLLocationDistance = 250_000) -> [RadioMapStation] {
        guard stations.count > 2 else { return stations }
        let middle = CLLocation(
            latitude: median(stations.map(\.latitude)),
            longitude: median(stations.map(\.longitude))
        )
        let near = stations.filter { $0.point.distance(from: middle) <= radius }
        return near.isEmpty ? stations : near
    }

    /// The region that shows every one of `stations`, with room around
    /// them for their pins, and no closer in than `minimumSpan` degrees.
    static func region(fitting stations: [RadioMapStation], minimumSpan: Double = 0.15) -> MKCoordinateRegion? {
        guard let first = stations.first else { return nil }
        var minLatitude = first.latitude, maxLatitude = first.latitude
        var minLongitude = first.longitude, maxLongitude = first.longitude
        for station in stations.dropFirst() {
            minLatitude = min(minLatitude, station.latitude)
            maxLatitude = max(maxLatitude, station.latitude)
            minLongitude = min(minLongitude, station.longitude)
            maxLongitude = max(maxLongitude, station.longitude)
        }
        return MKCoordinateRegion(
            center: CLLocationCoordinate2D(
                latitude: (minLatitude + maxLatitude) / 2,
                longitude: (minLongitude + maxLongitude) / 2
            ),
            // Half again the stations' spread. The default floor is about a
            // town, so one station isn't shown street by street.
            span: MKCoordinateSpan(
                latitudeDelta: min(170, max(minimumSpan, (maxLatitude - minLatitude) * 1.5)),
                longitudeDelta: min(360, max(minimumSpan, (maxLongitude - minLongitude) * 1.5))
            )
        )
    }

    private static func median(_ values: [Double]) -> Double {
        let sorted = values.sorted()
        return sorted[sorted.count / 2]
    }
}

/// A station with a point on the Radio map.
struct RadioMapStation: Identifiable, Hashable {
    let station: PlayableContent
    let latitude: Double
    let longitude: Double
    /// The place TuneIn names for it, "Seattle, WA".
    let location: String?

    var id: String { station.id }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var point: CLLocation {
        CLLocation(latitude: latitude, longitude: longitude)
    }
}

/// Stations close enough on the map to share one pin. Zoomed in, a pin is
/// usually one station; zoomed out, a city's worth.
struct RadioMapCluster: Identifiable {
    /// Never empty. The first leads: its logo is the pin's.
    let stations: [RadioMapStation]
    let latitude: Double
    let longitude: Double
    /// The place TuneIn names for every one of the stations, when they
    /// share one.
    let sharedLocation: String?
    /// The place the stations share, else the one station's name, else
    /// how many there are.
    let title: String

    /// Works out the names once: each pin reads them on every redraw of
    /// the map.
    init(stations: [RadioMapStation], latitude: Double, longitude: Double) {
        self.stations = stations
        self.latitude = latitude
        self.longitude = longitude
        let locations = Set(stations.map(\.location))
        let shared: String? = locations.count == 1 ? locations.first ?? nil : nil
        sharedLocation = shared
        title = shared ?? (stations.count == 1 ? stations[0].station.title : "\(stations.count) Stations")
    }

    /// The lead station's: a station is in one cluster at a time, and the
    /// pin keeps its identity while others join and leave it.
    var id: String { stations[0].id }

    var lead: PlayableContent { stations[0].station }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// Whether every station sits at one point, which zooming in would
    /// never pull apart. TuneIn often places a city's stations at the
    /// city itself.
    var isOnePlace: Bool {
        let latitudes = stations.map(\.latitude)
        let longitudes = stations.map(\.longitude)
        guard let minLatitude = latitudes.min(), let maxLatitude = latitudes.max(),
              let minLongitude = longitudes.min(), let maxLongitude = longitudes.max() else { return true }
        // About 500 m.
        return maxLatitude - minLatitude < 0.005 && maxLongitude - minLongitude < 0.005
    }

    var accessibilityLabel: String {
        stations.count == 1 ? stations[0].station.title : "\(title), \(stations.count) stations"
    }

    /// The pins for a map showing `region` in `size` points: stations on
    /// one cell of a grid share a pin, the cells about `pinSize` across on
    /// screen, so pins don't stack.
    static func clusters(
        of stations: [RadioMapStation],
        in region: MKCoordinateRegion?,
        size: CGSize,
        pinSize: CGFloat
    ) -> [RadioMapCluster] {
        guard let region, size.width > 0, size.height > 0 else {
            return stations.map { RadioMapCluster(stations: [$0], latitude: $0.latitude, longitude: $0.longitude) }
        }
        return clusters(
            of: stations,
            latitudeCell: region.span.latitudeDelta * pinSize / size.height,
            longitudeCell: region.span.longitudeDelta * pinSize / size.width
        )
    }

    /// Stations grouped by the grid cell, `latitudeCell` by
    /// `longitudeCell` degrees, they fall in, each pin at the middle of its
    /// stations. Cells too small to group anything leave every station its
    /// own pin.
    static func clusters(of stations: [RadioMapStation], latitudeCell: Double, longitudeCell: Double) -> [RadioMapCluster] {
        guard latitudeCell.isFinite, longitudeCell.isFinite,
              latitudeCell > 1e-7, longitudeCell > 1e-7 else {
            return stations.map { RadioMapCluster(stations: [$0], latitude: $0.latitude, longitude: $0.longitude) }
        }

        struct Cell: Hashable {
            let x: Int
            let y: Int
        }
        var members: [Cell: [RadioMapStation]] = [:]
        var order: [Cell] = []
        for station in stations {
            let cell = Cell(
                x: Int((station.longitude / longitudeCell).rounded(.down)),
                y: Int((station.latitude / latitudeCell).rounded(.down))
            )
            if members[cell] == nil {
                order.append(cell)
            }
            members[cell, default: []].append(station)
        }
        return order.compactMap { cell in
            guard let group = members[cell], !group.isEmpty else { return nil }
            let count = Double(group.count)
            return RadioMapCluster(
                stations: group,
                latitude: group.map(\.latitude).reduce(0, +) / count,
                longitude: group.map(\.longitude).reduce(0, +) / count
            )
        }
    }
}
