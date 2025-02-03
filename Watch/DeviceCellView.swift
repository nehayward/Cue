import Nuke
import NukeUI
import SwiftUI
import SonosKitMini
import MusicSearchKit

struct DeviceCellView: View {
    @Environment(SonosMiniService.self) private var sonosService: SonosMiniService
    let id: String
    
    var body: some View {
        if let device = sonosService.devices.first(where: { $0.id == id }) {
            Section {
                if device.state == .active {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading) {
                            if device.isTVMode {
                                Text(device.TVSettings?.audioInputFormat?.description ?? "--")
                                    .frame(maxWidth: .infinity, alignment: .center)
                            } else {
                                HStack {
                                    ThumbnailView(id: device.id, size: .small)
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
                } else {
                    VStack(spacing: 12) {
                        Text(device.state.reason)
                    }
                }
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
            .overlay(alignment: .center) {
                if sonosService.sorted.isEmpty {
                    ProgressView()
                }
            }
        }
    }
    
    @ViewBuilder
    var playbackView: some View {
        if let device = sonosService.devices.first(where: { $0.id == id }) {
            if !device.isTVMode && device.track != .empty {
                Button {
                    Task {
                        if device.isPlaying {
                            WKInterfaceDevice.current().play(.click)
                            await sonosService.pause(IP: device.ip)
                        } else {
                            WKInterfaceDevice.current().play(.click)
                            await sonosService.play(device.ip)
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
}



//#Preview {
//    DeviceCellView(group: .constant(.theater))
//        .environment(SonosService())
//}
