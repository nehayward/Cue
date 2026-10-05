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
                // Its own font: left to the List's, a selected sidebar row
                // turned the title bold.
                .font(.body)
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
