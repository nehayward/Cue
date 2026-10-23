import MapKit
import SonosKit
import SwiftUI

/// The Radio map, full screen: every station the map has placed (the ones
/// near you, and whatever Search This Area found) as pins that group while
/// zoomed out. A pin of one place opens its stations in a card to play; a
/// pin spanning several places zooms in on them. Stations Near You finds
/// where this device is (asking for location the first time) and the
/// stations there. Pushed from the Radio tab's tile, out of which it zooms,
/// so the mini player stays in reach.
struct RadioMapScreen: View {
    @State private var radioMap = RadioMap.shared
    @State private var tuneIn = TuneInBrowseService.shared
    @Environment(\.openURL) private var openURL

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var size: CGSize = .zero
    /// The pin last tapped, as it was then: its card stays put while the
    /// pins regroup under it.
    @State private var selected: RadioMapCluster?
    /// Whether the map has been set on the stations near you, which waits
    /// for the first of them to be placed when none were yet.
    @State private var hasFramed = false
    /// Stations Near You is waiting on where this device is.
    @State private var isFindingYou = false
    @State private var showsLocationOff = false

    private static let pinSize: CGFloat = 40
    /// How much of the map around you Stations Near You shows: about a
    /// metro area, what TuneIn's local page covers.
    private static let aroundYou: CLLocationDistance = 60_000

    private var localStations: [RadioMapStation] {
        radioMap.mapped(tuneIn.localStations)
    }

    private var stations: [RadioMapStation] {
        radioMap.mapped(tuneIn.localStations + radioMap.explored)
    }

    var body: some View {
        // Each of these walks every station, so once a redraw, not once
        // for each place that asks.
        let local = localStations
        let nearYou = Self.nearYouRegion(local)
        let barStatus = status(nearYou: nearYou)
        let selectedID = selected?.id
        let clusters = RadioMapCluster.clusters(
            of: stations,
            // Before the map reports where it's looking, where it was set.
            in: visibleRegion ?? nearYou,
            size: size,
            pinSize: Self.pinSize * 1.2
        )

        Map(position: $position) {
            // Only drawn once location is allowed; it never asks itself.
            UserAnnotation()

            ForEach(clusters) { cluster in
                Annotation(cluster.title, coordinate: cluster.coordinate, anchor: .center) {
                    Button {
                        open(cluster)
                    } label: {
                        RadioMapPin(
                            lead: cluster.lead,
                            count: cluster.stations.count,
                            isSelected: cluster.stations.contains { $0.id == selectedID },
                            size: Self.pinSize
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(cluster.accessibilityLabel)
                }
                .annotationTitles(.hidden)
            }
        }
        // Flat: the 3D buildings and terrain a city loads at street level
        // are most of a live map's memory, and nothing here needs them.
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            size = newSize
        }
        // Over the map, not a safe-area inset: an inset that comes, goes
        // and changes height moves the map's centre each time, so the pins
        // jumped as the bar changed.
        .overlay(alignment: .top) {
            RadioMapStatusBar(status: barStatus) { latitude, longitude in
                withAnimation(.snappy) {
                    selected = nil
                }
                Task {
                    await radioMap.searchArea(latitude: latitude, longitude: longitude)
                }
            }
            .padding(.top, 8)
        }
        .safeAreaInset(edge: .bottom) {
            if let selected {
                RadioMapStationsCard(cluster: selected) {
                    withAnimation(.snappy) {
                        self.selected = nil
                    }
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .navigationTitle("Radio Map")
#if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Stations Near You", systemImage: "location") {
                    findYou()
                }
            }
        }
        .alert("Location Is Off for Cue", isPresented: $showsLocationOff) {
            Button("Settings") {
                openLocationSettings()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("To find the stations where you are, allow Cue to use your location in Settings.")
        }
        .onAppear {
            // The view the tile shows, so the zoom lands on the same map.
            // Here rather than in `init`, which the screen that pushes this
            // runs in its body, so reading the places there would redraw
            // that screen with every station placed.
            guard !hasFramed, let nearYou else { return }
            hasFramed = true
            position = .region(nearYou)
        }
        .task {
            await radioMap.locate(tuneIn.localStations)
        }
        .onChange(of: local.map(\.id)) {
            // Opened before any station near you had a place: the first
            // ones to land set the view.
            guard !hasFramed else { return }
            frameNearYou()
        }
    }

    // MARK: - Pins

    /// Zooms in on a pin whose stations zooming would pull apart; opens the
    /// card for the rest. A pin of stations a little way apart, already as
    /// close in as their fit goes, opens too, or the tap would do nothing.
    private func open(_ cluster: RadioMapCluster) {
        if cluster.stations.count > 1, !cluster.isOnePlace,
           let region = RadioMap.region(fitting: cluster.stations, minimumSpan: 0.01),
           visibleRegion.map({ Self.isCloser(region, than: $0) }) ?? true {
            withAnimation(.smooth) {
                selected = nil
                position = .region(region)
            }
        } else {
            withAnimation(.snappy) {
                selected = cluster
            }
        }
    }

    private static func isCloser(_ region: MKCoordinateRegion, than visible: MKCoordinateRegion) -> Bool {
        region.span.latitudeDelta < visible.span.latitudeDelta * 0.8
            && region.span.longitudeDelta < visible.span.longitudeDelta * 0.8
    }

    // MARK: - Near You

    /// Finds where this device is and shows the stations there. Without
    /// location, the map goes to the stations TuneIn places near you by
    /// your IP address, which can be a city or more away.
    private func findYou() {
        guard !isFindingYou else { return }
        isFindingYou = true
        // From here the map goes where it's asked: stations near you
        // landing later don't take it back to TuneIn's guess.
        hasFramed = true
        Task {
            let outcome = await RadioMapLocator().currentLocation()
            isFindingYou = false
            switch outcome {
            case let .found(coordinate):
                show(coordinate)
            case .denied:
                frameNearYou()
                showsLocationOff = true
            case .unavailable:
                frameNearYou()
            }
        }
    }

    /// Moves the map to `coordinate` and asks TuneIn for the stations
    /// local to it, unless they were asked for already.
    private func show(_ coordinate: CLLocationCoordinate2D) {
        let region = MKCoordinateRegion(
            center: coordinate,
            latitudinalMeters: Self.aroundYou,
            longitudinalMeters: Self.aroundYou
        )
        withAnimation(.smooth) {
            selected = nil
            position = .region(region)
        }
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        guard !hasAsked(about: here, nearYou: Self.nearYouRegion(localStations), in: region) else { return }
        Task {
            await radioMap.searchArea(latitude: coordinate.latitude, longitude: coordinate.longitude)
        }
    }

    private func openLocationSettings() {
        #if targetEnvironment(macCatalyst)
        let address = "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
        #else
        let address = UIApplication.openSettingsURLString
        #endif
        if let url = URL(string: address) {
            openURL(url)
        }
    }

    private func frameNearYou() {
        guard let region = Self.nearYouRegion(localStations) else { return }
        hasFramed = true
        withAnimation(.smooth) {
            selected = nil
            position = .region(region)
        }
    }

    private static func nearYouRegion(_ stations: [RadioMapStation]) -> MKCoordinateRegion? {
        RadioMap.region(fitting: RadioMap.core(of: stations))
    }

    // MARK: - Status

    /// What the bar over the map says: work under way, else the offer to
    /// search where the map has moved to, else what the last search found.
    private func status(nearYou: MKCoordinateRegion?) -> RadioMapStatus? {
        if isFindingYou {
            return .working("Finding You…")
        }
        if radioMap.isSearchingArea {
            return .working("Searching This Area…")
        }
        if radioMap.isLocating {
            return .working("Placing Stations…")
        }
        if let center = searchCenter(nearYou: nearYou) {
            return .search(latitude: center.latitude, longitude: center.longitude)
        }
        if let notice {
            return .notice(notice)
        }
        return nil
    }

    /// The middle of the map, once it has moved off everywhere already
    /// asked about. Nil zoomed out past a region, where one point's local
    /// stations would be a speck.
    private func searchCenter(nearYou: MKCoordinateRegion?) -> CLLocationCoordinate2D? {
        guard let region = visibleRegion, region.span.latitudeDelta < 12 else { return nil }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        guard !hasAsked(about: center, nearYou: nearYou, in: region) else { return nil }
        return region.center
    }

    /// Whether TuneIn has been asked for the stations local to `point`:
    /// it's the same place, seen in `region`, as the stations near you or
    /// an area searched.
    private func hasAsked(about point: CLLocation, nearYou: MKCoordinateRegion?, in region: MKCoordinateRegion) -> Bool {
        let nearYouCenter = nearYou.map { CLLocation(latitude: $0.center.latitude, longitude: $0.center.longitude) }
        let asked = radioMap.searches.map(\.center) + [nearYouCenter].compactMap { $0 }
        return asked.contains { point.distance(from: $0) <= Self.samePlace(in: region) }
    }

    /// A search that placed none of its stations near where it asked:
    /// TuneIn lists nothing local there. Said while the map is still
    /// on that place.
    private var notice: String? {
        guard let search = radioMap.searches.last, let region = visibleRegion else { return nil }
        let center = CLLocation(latitude: region.center.latitude, longitude: region.center.longitude)
        guard center.distance(from: search.center) <= Self.samePlace(in: region) else { return nil }
        let placedNearby = radioMap.mapped(search.stations).contains { $0.point.distance(from: search.center) < 300_000 }
        return placedNearby ? nil : "No Stations Found Here"
    }

    /// How far the map's middle can move and still be the same place: half
    /// the view's height, and at least 20 km.
    private static func samePlace(in region: MKCoordinateRegion) -> CLLocationDistance {
        max(20_000, region.span.latitudeDelta * 111_000 / 2)
    }
}

/// What the bar over the Radio map says.
private enum RadioMapStatus: Equatable {
    case working(String)
    /// Search This Area, asking about this point.
    case search(latitude: Double, longitude: Double)
    case notice(String)

    var isSearch: Bool {
        if case .search = self { true } else { false }
    }

    var isWorking: Bool {
        if case .working = self { true } else { false }
    }

    var title: String {
        switch self {
        case let .working(text): text
        case .search: "Search This Area"
        case let .notice(text): text
        }
    }

    /// The mark beside the title; work under way shows a spinner instead.
    var symbol: String {
        switch self {
        case .working, .search: "magnifyingglass"
        case .notice: "antenna.radiowaves.left.and.right.slash"
        }
    }

    /// What the bar animates on. Not the point Search This Area would ask
    /// about, which moves with every pan and changes nothing on screen.
    var look: String {
        switch self {
        case let .working(text): "working:\(text)"
        case .search: "search"
        case let .notice(text): "notice:\(text)"
        }
    }
}

/// The bar over the Radio map: one glass capsule whose content changes, so
/// Search This Area turning into Searching and then going away is one
/// shape changing size, not a button and a label swapped under each other.
/// It only takes a tap while it offers the search; otherwise touches go
/// through to the map.
private struct RadioMapStatusBar: View {
    let status: RadioMapStatus?
    let search: (_ latitude: Double, _ longitude: Double) -> Void

    var body: some View {
        ZStack {
            if let status {
                capsule(status)
                    .transition(.scale(scale: 0.85, anchor: .top).combined(with: .opacity))
            }
        }
        // Scoped to the bar. On the whole map it also animated the pins
        // that landed in the same update, which flew in from nowhere.
        .animation(.snappy, value: status?.look)
    }

    private func capsule(_ status: RadioMapStatus) -> some View {
        Button {
            if case let .search(latitude, longitude) = status {
                search(latitude, longitude)
            }
        } label: {
            label(status)
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                // Its own width, always: squeezed by a capsule still
                // growing, the new words were cut short.
                .fixedSize()
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .radioMapGlass(in: .capsule)
        .allowsHitTesting(status.isSearch)
        .accessibilityRemoveTraits(status.isSearch ? [] : .isButton)
    }

    /// One mark and one title whatever the status, so a change is the
    /// title turning into the next, not one label fading out over another.
    private func label(_ status: RadioMapStatus) -> some View {
        HStack(spacing: 8) {
            // One slot for the mark, so the spinner and the symbol trade
            // places without moving the title.
            ZStack {
                if status.isWorking {
                    ProgressView()
                        .controlSize(.small)
                        .transition(.opacity)
                } else {
                    Image(systemName: status.symbol)
                        .transition(.opacity)
                }
            }
            .frame(width: 18, height: 18)

            Text(status.title)
                .contentTransition(Self.titleTransition)
        }
    }

    /// The title's glyphs move into the new words. Not on the Mac, where
    /// text redrawn as it changes holds ~90 MB of GPU memory for the run
    /// of it (see Mac GPU cost in CLAUDE.md); there the words just change.
    private static var titleTransition: ContentTransition {
        #if targetEnvironment(macCatalyst)
        .identity
        #else
        .interpolate
        #endif
    }
}

/// The stations of the pin last tapped, to play: the place they share and
/// a row for each, the rows the Radio tab's grid uses.
private struct RadioMapStationsCard: View {
    let cluster: RadioMapCluster
    let close: () -> Void

    /// A row is a 50 pt logo, spaced like the Radio tab's grid.
    private static let rowHeight: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(cluster.title)
                        .font(.headline)
                    if cluster.stations.count > 1, cluster.sharedLocation != nil {
                        Text("\(cluster.stations.count) Stations")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .lineLimit(1)
                Spacer(minLength: 0)
                Button("Close", systemImage: "xmark", action: close)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
            }

            ScrollView {
                // Lazy: a city's pin can hold dozens of stations, and each
                // row is a menu with its own artwork.
                LazyVStack(spacing: RadioGrid.spacing) {
                    ForEach(cluster.stations) { station in
                        PlayableContentRowView(item: station.station, hideSubtitle: true)
                            .buttonStyle(.plain)
                            .clipShape(.rect(cornerRadius: RadioGrid.cornerRadius))
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: listHeight)
        }
        .fontDesign(.rounded)
        .padding(16)
        .radioMapGlass(in: .rect(cornerRadius: 28, style: .continuous))
        .frame(maxWidth: 520)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    /// Every row up to three; past that, three and a half, so the cut-off
    /// row says the list scrolls.
    private var listHeight: CGFloat {
        let count = cluster.stations.count
        let row = Self.rowHeight + RadioGrid.spacing
        return count <= 3 ? row * CGFloat(count) - RadioGrid.spacing : row * 3.5 - RadioGrid.spacing
    }
}
