import MusicSearchKit
import NukeUI
import SonosKit
import SwiftUI
import Collections

struct QueueScreen: View {
    @Environment(SonosService.self) var sonosService: SonosService
    
    @Binding var group: GroupRoom
    @State private var router = Router()
    @State private var isLoading: Bool = true

    var body: some View {
        NavigationStack(path: $router.path) {
            ScrollViewReader { proxy in
                List {
                    ForEach(Array(group.coordinatorRoom.queue), id: \.trackID) { track in
                        Button {
                            Task {
                                guard let position = track.metadata?.position else { return }
                                await sonosService.seek(trackNumber: position, on: group)
                                await sonosService.play(ip: group.coordinatorRoom.ip)
                                group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                            }
                        } label: {
                            HStack {
                                ThumbnailView(content: track)
                                    .aspectRatio(contentMode: .fit)
                                    .frame(width: 40, height: 40)
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
//                        .swipeActions {
//                            Button(role: .destructive) {
//                                guard let position = track.metadata?.position else { return }
//                                group.coordinatorRoom.queue.remove(at: position - 1)
//                                Task {
//                                    try? await sonosService.removeTrackFromQueue(group.coordinatorRoom.ip, index: position)
//                                    group.coordinatorRoom.queue =  OrderedSet(await sonosService.getQueue(ip: group.ip))
//                                }
//                            } label: {
//                                Label("Delete", systemImage: "trash")
//                            }
//                        }
                        .listRowBackground(isTrackPlaying(for: track) ? nil : Color.clear)
                        .bold(isTrackPlaying(for: track))
                    }
                }
                .saturation(group.playbackService == .queue ? 1 : 0.1 )
                .listStyle(.plain)
                .task(id: group.coordinatorRoom.track.trackID) {
                    isLoading = true
                    group.playMode = await sonosService.playMode(ip: group.ip)
                    let id = group.coordinatorRoom.track.trackID + "\(group.coordinatorRoom.track.position)"
                    proxy.scrollTo(id, anchor: .top)
                    self.group.coordinatorRoom.queue = OrderedSet(await sonosService.getQueue(ip: group.coordinatorRoom.ip))
                    isLoading = false
                }
                .animation(.spring, value: group.coordinatorRoom.queue)
                .navigationBarTitle(navigationTitle)
            }
        }
        .overlay {
            if isLoading, group.coordinatorRoom.queue.isEmpty {
                ProgressView()
            }
            if group.coordinatorRoom.queue.isEmpty, !isLoading {
                ContentUnavailableView("Empty", systemImage: "music.note.list")
                    .transition(.opacity)
            }
        }
        .overlay(alignment: .bottom) {
            if group.playbackService != .queue  {
                Text("Queue Not Active")
                    .padding()
                    .background(.thickMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
        .fontDesign(.rounded)
        .animation(.default, value: group.playbackService)
    }

    private func isTrackPlaying(for song: PlayableContent) -> Bool {
        guard let position = song.metadata?.position else { return false }
        return group.coordinatorRoom.track.position == position && group.playbackService == .queue
    }
    
    private var navigationTitle: Text {
        Text("Queue \(!group.coordinatorRoom.queue.isEmpty ? " " : "")") +
        Text(group.coordinatorRoom.queue.count, format: .number)
    }
}

fileprivate struct ContainerView: View {
    @State var group: GroupRoom = .garage
    var body: some View {
        QueueScreen(group: $group)
            .environment(SonosService())
    }
}

#Preview {
    TabView {
        ContainerView()
    }
}

