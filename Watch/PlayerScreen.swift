import SwiftUI
import SonosKitMini
import NukeUI

struct PlayerScreen: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosMiniService.self) var sonosService: SonosMiniService
    
    @State var tabSelection: Int = 0
    
    var id: String
    
    var body: some View {
        Group {
            if let index = sonosService.devices.firstIndex(where: { $0.id == id }) {
                let device = sonosService.devices[index]
                if !device.isHidden {
                    TabView(selection: $tabSelection) {
                        Group {
                            if device.isTVMode {
                                TVView(id: id)
                                    .transition(.scale.combined(with: .opacity))
                            } else {
                                PlayerView(id: id)
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        GroupVolumeControlScreen(id: id)
                        UpNextScreen(id: id)
                    }
                    .animation(.interactiveSpring, value: device.isTVMode)
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
                    ThumbnailView(id: device.id, size: .small)
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
