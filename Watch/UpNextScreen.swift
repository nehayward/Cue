import MusicSearchKit
import NukeUI
import SwiftUI
import Collections
import SonosKitMini

struct UpNextScreen: View {
    @Environment(\.scenePhase) var scenePhase
    @Environment(SonosMiniService.self) private var sonosService: SonosMiniService
    @Environment(Popover.self) var popOver: Popover
    
    let id: String
    
    @State private var isLoading: Bool = false
    
    
    var body: some View {
        @Bindable var sonosService = sonosService
        
        if let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }) {
            deviceView(for: deviceIndex)
        } else {
            Text("Vanished")
        }
    }
    
    @ViewBuilder
    func deviceView(for index: Int) -> some View {
        let device = sonosService.devices[index]
        
        ScrollViewReader { proxy in
            List {
                ForEach(Array(device.queue), id: \.trackID) { track in
                    Button {
                        Task {
                            guard let position = track.metadata?.position else { return }
                            await sonosService.seek(to: position, on: device)
                            await sonosService.play(device.ip)
                        }
                    } label: {
                        HStack {
                            Text(track.metadata?.position?.description ?? "-")
                                .frame(width: 20, alignment: .center)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                                .allowsTightening(true)
                                .minimumScaleFactor(0.5)
                            VStack(alignment: .leading) {
                                Text(track.title)
                                    .lineLimit(1)
                                Text(track.subtitle)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                    }
                }
            }
            .saturation(device.playbackService == .queue ? 1 : 0.1 )
            .listStyle(.plain)
            .task {
                isLoading = true
                await sonosService.updateQueue(for: device, total: 50)
                isLoading = false
            }
            .animation(.spring, value: device.queue)
            .navigationBarTitle("Up Next")
        }
        .overlay {
            if isLoading, device.queue.isEmpty {
                ProgressView()
            }
            if device.queue.isEmpty, !isLoading {
                ContentUnavailableView("Empty", systemImage: "music.note.list")
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if device.playbackService != .queue  {
                Text("Not Active")
                    .padding(8)
                    .background(.thinMaterial)
                    .clipShape(Capsule())
                    .offset(y: -10)
            }
        }
        .fontDesign(.rounded)
    }
}

