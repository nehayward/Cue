import SwiftUI

struct ZoneView: View {
    let radioStation: String
    let song: String
    let artist: String

    var body: some View {
        VStack(alignment: .leading) {
            Text(radioStation)
                .font(.caption.smallCaps())
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .lineLimit(1, reservesSpace: true)
            Text(song)
                .foregroundStyle(.primary)
                .tint(.primary)
                .lineLimit(1, reservesSpace: true)
            Text(artist)
                .font(.callout)
                .foregroundStyle(.secondary)
                .tint(.secondary)
                .lineLimit(1, reservesSpace: true)
        }
        .frame(alignment: .top)
        .fontDesign(.rounded)
    }
}
