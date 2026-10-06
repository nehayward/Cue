import MapKit
import SonosKit
import SwiftUI

/// The Radio tab's map: the stations near you, placed where they broadcast
/// from, on a small map that zooms into the full one (`RadioMapScreen`)
/// when tapped. The tile is a button, so the map under it is drawn but
/// takes no touches.
struct RadioMapTile: View {
    let stations: [RadioMapStation]
    let isLocating: Bool

    @Environment(\.horizontalSizeClass) private var sizeClass

    @State private var position: MapCameraPosition = .automatic
    @State private var visibleRegion: MKCoordinateRegion?
    @State private var size: CGSize = .zero

    private static let pinSize: CGFloat = 28

    /// The stations near you, leaving out the far-off networks TuneIn's
    /// local page carries; the full map opens on the same view.
    private var framing: MKCoordinateRegion? {
        RadioMap.region(fitting: RadioMap.core(of: stations))
    }

    var body: some View {
        let clusters = RadioMapCluster.clusters(
            of: stations,
            in: visibleRegion ?? framing,
            size: size,
            pinSize: Self.pinSize * 1.2
        )

        Map(position: $position, interactionModes: []) {
            ForEach(clusters) { cluster in
                Annotation(cluster.title, coordinate: cluster.coordinate, anchor: .center) {
                    RadioMapPin(cluster: cluster, size: Self.pinSize)
                }
                .annotationTitles(.hidden)
            }
        }
        .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            visibleRegion = context.region
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { newSize in
            size = newSize
        }
        .allowsHitTesting(false)
        .frame(height: sizeClass == .compact ? 190 : 260)
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
        // Stations land one by one as their places come back; the view
        // follows them until they're all in.
        .onChange(of: stations.map(\.id), initial: true) {
            guard let framing else { return }
            withAnimation(.smooth) {
                position = .region(framing)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Radio Map")
        .accessibilityValue(captionText)
        .accessibilityHint("Opens a map of radio stations")
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

/// A pin on the Radio map: the lead station's logo on a white tile and,
/// when the pin stands for more than one station, how many.
struct RadioMapPin: View {
    let cluster: RadioMapCluster
    var isSelected = false
    var size: CGFloat = 40

    private var cornerRadius: CGFloat { size * 0.24 }

    var body: some View {
        ContentArtworkView(content: cluster.lead, showMusicSource: false, cornerRadius: cornerRadius)
            .frame(width: size, height: size)
            // Logos are often drawn on nothing; the tile gives them a ground.
            .background(.white, in: .rect(cornerRadius: cornerRadius, style: .continuous))
            .padding(isSelected ? 3 : 2)
            .background(
                isSelected ? Color.accentColor : Color.white,
                in: .rect(cornerRadius: cornerRadius + 3, style: .continuous)
            )
            .shadow(color: .black.opacity(0.3), radius: 3, y: 1)
            .overlay(alignment: .topTrailing) {
                if cluster.stations.count > 1 {
                    Text(cluster.stations.count, format: .number)
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
