import MusicSearchKit
import NukeUI
import SwiftUI
import Collections
import SonosKitMini

struct UpNextScreen: View {
    var device: SonosDevice
    
    @State private var isLoading: Bool = false
    @State private var upNext: [PlayableContent] = []
    
    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    HStack {
                        ThumbnailView(device: device, size: .small)
                            .frame(width: 40, height: 40)
                        VStack(alignment: .leading) {
                            Text(device.track.name)
                                .lineLimit(1)
                            Text(device.track.artist)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .id("Now Playing")
                } header: {
                    Text("Now Playing")
                }
                
                ForEach(upNext, id: \.trackID) { track in
                    Button {
                        Task {
                            guard let position = track.metadata?.position else { return }
                            await SonosMiniService.shared.seek(to: position, on: device)
                            await SonosMiniService.shared.play(device.ip)
                            upNext = await SonosMiniService.shared.getQueue(ip: device.ip, with: device.track.position)
                            withAnimation {
                                proxy.scrollTo("Now Playing", anchor: .top)
                            }
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
                if upNext.isEmpty, !isLoading {
                    ContentUnavailableView("Empty", systemImage: "music.note.list")
                        .transition(.opacity)
                }
            }
        }
        .task {
            isLoading = true
            upNext = await SonosMiniService.shared.getQueue(ip: device.ip, with: device.track.position)
            isLoading = false
        }
        .navigationBarTitle("Up Next")
        .overlay {
            if isLoading, upNext.isEmpty {
                ProgressView()
            }
        }
        .fontDesign(.rounded)
    }
}

