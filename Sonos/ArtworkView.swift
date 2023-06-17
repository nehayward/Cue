import SwiftUI
import SonosKit

struct ArtworkView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var device: SonosDevice
    @State var url: URL?

    var body: some View {
        HStack {
            AsyncImage(
                        url: url,
                        transaction: Transaction(animation: .snappy)
                    ) { phase in
                        switch phase {
                        case .success(let image):
                            image
                                .resizable()
                                .frame(width: 100, height: 100)
                        default:
                            Color.blue
                                .frame(width: 100, height: 100)
                        }
                    }
        }
        .task {
            guard let track = await sonosService.getTrack(ip: device.ipAddress) else { return }
            guard let artworkURL = await sonosService.getArtwork(song: track.name, artist: track.artist, album: track.album) else {
                return
            }
            url = artworkURL
            
        }
    }
}
//
//#Preview {
//    ArtworkView(device: SonosDevice(name: "Kitchen", ipAddress: "192.168.4.153", volume: 0))
//        .environment(SonosService())
//}
//
