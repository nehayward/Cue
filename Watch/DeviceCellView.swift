import Nuke
import NukeUI
import SwiftUI
import SonosKitMini
import MusicSearchKit

struct DeviceCellView: View {
    var device: SonosDevice
    
    var body: some View {
//        let _ = Self._printChanges()
            
        Section {
            HStack(spacing: 0) {
                VStack(alignment: .leading) {
                    if device.isTVMode {
                        Text(device.TVSettings?.audioInputFormat?.description ?? "--")
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        HStack {
                            ThumbnailView(device: device, size: .small)
                                .frame(width: 40, height: 40)
                            VStack(alignment: .leading) {
                                Text(device.track.song)
                                    .lineLimit(1, reservesSpace: true)
                                Text(device.track.artist)
                                    .lineLimit(1, reservesSpace: true)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            playbackView
                        }
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 0))
        } header: {
            HStack {
                Text(device.nameWithCount)
                if let battery = device.battery {
                    Spacer()
                    Text((battery.percentage / 100), format: .percent)
                        .foregroundStyle(.secondary)
                    if battery.chargingState == .charging {
                        Image(systemName: "battery.100percent.bolt")
                            .symbolRenderingMode(.hierarchical)
                            .font(.caption)
                            .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                    }
                }
            }
            .fontDesign(.rounded)
            .headerProminence(.increased)
        }
    }
    
    @ViewBuilder
    var playbackView: some View {
        if !device.isTVMode && device.track != .empty {
            Button {
                Task {
                    if device.isPlaying {
                        WKInterfaceDevice.current().play(.click)
                        await SonosMiniService.shared.pause(IP: device.ip)
                    } else {
                        WKInterfaceDevice.current().play(.click)
                        await SonosMiniService.shared.play(device.ip)
                    }
                }
            } label: {
                Image(systemName: device.isPlaying ? "pause" : "play")
                    .contentTransition(.symbolEffect(.automatic))
                    .frame(width: 20, height: 40, alignment: .center)
                    .symbolVariant(.fill)
            }
            .buttonStyle(.liveActivity)
        }
    }
}



//#Preview {
//    DeviceCellView(group: .constant(.theater))
//        .environment(SonosService())
//}
