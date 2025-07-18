import SwiftUI
import SonosKitMini
import NukeUI

struct PlayerScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosMiniService.self) var sonosService: SonosMiniService
    
    let id: String
    
    @State var selection: PlayerScreenSelection = .main
    
    var body: some View {
        @Bindable var sonosService = sonosService
        VStack {
            if let index = sonosService.devices.firstIndex(where: { $0.id == id }) {
                let device = sonosService.devices[index]
                if !device.isHidden {
                    TabView(selection: $selection) {
//                        PlayHistoryView(id: device.id)
//                            .tag(PlayerScreenSelection.favorites)
                        PlayerView(device: $sonosService.devices[index])
                            .tag(PlayerScreenSelection.main)
                        GroupVolumeControlScreen(device: device)
                            .tag(PlayerScreenSelection.volume)
                        UpNextScreen(device: device)
                            .tag(PlayerScreenSelection.upNext)
                    }
                } else {
                    Text("No Longer Group")
                        .task {
                            dismiss()
                        }
                }
            } else {
                Text("No Longer Group")
                    .task {
                        dismiss()
                    }
            }
        }
        .containerBackground(for: .navigation) {
            if let index = sonosService.devices.firstIndex(where: { $0.id == id }) {
                let device = sonosService.devices[index]
                ZStack {
                    ThumbnailView(device: device, size: .small)
                        .saturation(1.3)
                        .aspectRatio(contentMode: .fill)
                        .scaleEffect(1.3)
                        .blur(radius: 24)
                    Rectangle()
                        .foregroundStyle(.thinMaterial)
                        .scaleEffect(1.3)
                }
                .ignoresSafeArea()
            } else {
                Rectangle()
                    .aspectRatio(contentMode: .fit)
                    .foregroundStyle(.fill)
                    .shadow(radius: 2)
                    .ignoresSafeArea()
            }
        }
    }
}

extension PlayerScreen {
    enum PlayerScreenSelection {
        case favorites
        case main
        case volume
        case upNext
    }
}
