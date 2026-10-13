import MapKit
import SonosKit
import SwiftUI

/// The Radio tab's map: the stations near you, placed where they broadcast
/// from, on a small map that zooms into the full one (`RadioMapScreen`)
/// when tapped. A picture of the map (`MKMapSnapshotter`) with the pins
/// drawn over it, not a live `Map`: a live map view holds its renderer and
/// tiles, and the one in the list stayed alive under the full map once
/// that was pushed, so there were two. The picture is a couple of MB, and
/// the full map is the only live one.
struct RadioMapTile: View {
    let stations: [RadioMapStation]
    let isLocating: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.displayScale) private var displayScale

    /// Starts from the last picture drawn, so a tile scrolled away and
    /// back, or the tab reopened, doesn't draw the same map again.
    @State private var rendered: RenderedMap? = RadioMapTile.lastRendered
    @State private var size: CGSize = .zero

    private static let pinSize: CGFloat = 28
    private static var lastRendered: RenderedMap?

    /// The stations near you, leaving out the far-off networks TuneIn's
    /// local page carries; the full map opens on the same view.
    private var framing: MKCoordinateRegion? {
        RadioMap.region(fitting: RadioMap.core(of: stations))
    }

    /// Everything the picture depends on. Nil until there's a place to
    /// show and a size to draw it at.
    private var snapshotKey: SnapshotKey? {
        guard let framing, size.width > 0, size.height > 0 else { return nil }
        return SnapshotKey(
            latitude: framing.center.latitude,
            longitude: framing.center.longitude,
            latitudeDelta: framing.span.latitudeDelta,
            longitudeDelta: framing.span.longitudeDelta,
            width: size.width,
            height: size.height,
            isDark: colorScheme == .dark,
            scale: displayScale
        )
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Rectangle()
                .fill(.fill.tertiary)
            if let rendered {
                Image(uiImage: rendered.snapshot.image)
                    .resizable()
                    .frame(width: rendered.key.width, height: rendered.key.height)
                ForEach(clusters(on: rendered)) { cluster in
                    RadioMapPin(lead: cluster.lead, count: cluster.stations.count, size: Self.pinSize)
                        .position(rendered.snapshot.point(for: cluster.coordinate))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: sizeClass == .compact ? 190 : 260)
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            size = newSize
        }
        .clipShape(.rect(cornerRadius: RadioGrid.cornerRadius, style: .continuous))
        .overlay {
            // A hairline, as the station covers have, so the map's edge
            // holds against a screen of the same colour.
            RoundedRectangle(cornerRadius: RadioGrid.cornerRadius, style: .continuous)
                .strokeBorder(.quaternary, lineWidth: 0.5)
        }
        .overlay(alignment: .bottomLeading) {
            caption
                .padding(10)
        }
        .overlay(alignment: .topTrailing) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .frame(width: 30, height: 30)
                .radioMapGlass(in: .circle)
                .padding(10)
        }
        .contentShape(.rect(cornerRadius: RadioGrid.cornerRadius))
        .task(id: snapshotKey) {
            await render(snapshotKey)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radio Map")
        .accessibilityValue(captionText)
        .accessibilityHint("Opens a map of radio stations")
    }

    /// Draws the map for `key`, unless that's the picture already shown.
    private func render(_ key: SnapshotKey?) async {
        guard let key, let framing, rendered?.key != key else { return }
        // Stations land in bursts as their places come back; with a
        // picture already up, wait for a pause rather than drawing the map
        // once for each. A new key cancels this task, and so the wait.
        if rendered != nil {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
        }

        let configuration = MKStandardMapConfiguration(elevationStyle: .flat, emphasisStyle: .muted)
        configuration.pointOfInterestFilter = .excludingAll
        let options = MKMapSnapshotter.Options()
        options.preferredConfiguration = configuration
        options.region = framing
        options.size = CGSize(width: key.width, height: key.height)
        options.traitCollection = UITraitCollection { traits in
            traits.userInterfaceStyle = key.isDark ? .dark : .light
            traits.displayScale = key.scale
        }

        guard let snapshot = try? await MKMapSnapshotter(options: options).start(),
              !Task.isCancelled else { return }
        let map = RenderedMap(snapshot: snapshot, key: key)
        rendered = map
        Self.lastRendered = map
    }

    /// The pins for the picture, grouped so they don't stack. The picture
    /// widens the region asked for to the tile's shape, so the scale comes
    /// off the picture itself rather than the region.
    private func clusters(on map: RenderedMap) -> [RadioMapCluster] {
        let center = CLLocationCoordinate2D(latitude: map.key.latitude, longitude: map.key.longitude)
        let step = 0.01
        let origin = map.snapshot.point(for: center)
        let east = map.snapshot.point(for: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude + step))
        let north = map.snapshot.point(for: CLLocationCoordinate2D(latitude: center.latitude + step, longitude: center.longitude))
        let pointsPerLongitude = Double(abs(east.x - origin.x)) / step
        let pointsPerLatitude = Double(abs(north.y - origin.y)) / step
        let cell = Double(Self.pinSize) * 1.2
        guard pointsPerLongitude > 0, pointsPerLatitude > 0 else {
            return RadioMapCluster.clusters(of: stations, latitudeCell: 0, longitudeCell: 0)
        }
        return RadioMapCluster.clusters(
            of: stations,
            latitudeCell: cell / pointsPerLatitude,
            longitudeCell: cell / pointsPerLongitude
        )
    }

    private var caption: some View {
        HStack(spacing: 6) {
            if isLocating {
                ProgressView()
                    .controlSize(.mini)
            }
            Text(captionText)
        }
        .font(.footnote.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .radioMapGlass(in: .capsule)
    }

    private var captionText: String {
        switch stations.count {
        case 0: isLocating ? "Finding Stations…" : "No Stations Placed Yet"
        case 1: "1 Station"
        default: "\(stations.count) Stations"
        }
    }
}

/// What a tile's picture was drawn for: the region, the size in points,
/// the appearance and the screen's scale.
private struct SnapshotKey: Hashable {
    let latitude: Double
    let longitude: Double
    let latitudeDelta: Double
    let longitudeDelta: Double
    let width: Double
    let height: Double
    let isDark: Bool
    let scale: Double
}

/// A tile's picture of the map, and what it was drawn for.
private struct RenderedMap {
    let snapshot: MKMapSnapshotter.Snapshot
    let key: SnapshotKey
}

/// A pin on the Radio map: the lead station's logo on a white tile and,
/// when the pin stands for more than one station, how many. Equatable on
/// what it draws, so a redraw of the map that leaves a pin as it was
/// leaves it alone.
struct RadioMapPin: View, Equatable {
    let lead: PlayableContent
    let count: Int
    var isSelected = false
    var size: CGFloat = 40

    private var cornerRadius: CGFloat { size * 0.24 }

    var body: some View {
        ContentArtworkView(content: lead, showMusicSource: false, cornerRadius: cornerRadius)
            .frame(width: size, height: size)
            // Logos are often drawn on nothing; the tile gives them a ground.
            .background(.white, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .padding(isSelected ? 3 : 2)
            .background {
                // The shadow is the frame's alone. On the whole pin it
                // would draw the logo and badge offscreen to find their
                // edge, for every pin on the map.
                RoundedRectangle(cornerRadius: cornerRadius + 3, style: .continuous)
                    .fill(isSelected ? Color.accentColor : Color.white)
                    .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            }
            .overlay(alignment: .topTrailing) {
                if count > 1 {
                    Text(count, format: .number)
                        .font(.caption2.weight(.bold))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 18, minHeight: 18)
                        .background(Color.accentColor, in: .capsule)
                        .overlay {
                            Capsule()
                                .strokeBorder(.white, lineWidth: 1.5)
                        }
                        .offset(x: 7, y: -7)
                }
            }
            .scaleEffect(isSelected ? 1.2 : 1)
            .animation(.snappy, value: isSelected)
    }
}

extension View {
    /// Glass in `shape` for the map's floating labels and cards, or a
    /// material where there's no glass.
    @ViewBuilder
    func radioMapGlass<S: Shape>(in shape: S) -> some View {
#if !os(visionOS)
        if #available(iOS 26.0, macOS 26.0, *) {
            glassEffect(.regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
        }
#else
        background(.regularMaterial, in: shape)
#endif
    }
}
