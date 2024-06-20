import SwiftUI
import SonosKit
import VibesDS
import CloudStorage
import Defaults
import NukeUI
import MusicKit
import OrderedCollections

struct QueueListView: View {
    var sonosService: SonosService = .shared

    @State var playableContent: PlayableContent? = nil
    @State var isQueueing: Bool = false
    @State private var playHistoryService = PlayHistoryService()
    var viewModel: ViewModel
    var context: NSExtensionContext?

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack {
            VStack {
                if let playableContent = playableContent {
                    HStack(alignment: .top) {
                        AsyncImage(url: playableContent.artwork) { image in
                            image
                                .resizable()
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .overlay(alignment: .bottomTrailing) {
                                    playableContent.content.service.icon
                                        .frame(width: 16)
                                        .padding([.bottom, .trailing], 4)
                                }
                        } placeholder: {
                            ProgressView()
                        }
                        .transition(.scale)
                        .aspectRatio(contentMode: .fill)
                        .frame(width: 100, height: 100)
                        VStack(alignment: .leading) {
                            Text(playableContent.title)
                            Text("\(playableContent.content.type.title)\(playableContent.subtitle.isEmpty ? "" : " • \(playableContent.subtitle)")")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fontDesign(.rounded)
                    }
                    .padding(.horizontal)

                    List($sonosService.sorted) { $group in
                        VStack(alignment: .leading) {
                            Button {
                                isQueueing = true
                                impactFeedbackGenerator.impactOccurred()
                                Task {
                                    playHistoryService.history.remove(playableContent)
                                    playHistoryService.history.insert(playableContent, at: 0)
                                    await sonosService.queue(playable: playableContent, group: group, position: .now)
                                    await sonosService.play(ip: group.ip)
                                    self.context?.completeRequest(returningItems: [])
                                }
                            } label: {
                                Text(group.nameWithCount)
                                    .fontDesign(.rounded)
                                    .bold()
                            }
                            VolumeControlView(volume: $group.groupVolume) { volume in
                                Task {
                                    await sonosService.setGroupVolume(ip: group.ip, volume: Int(volume))
                                }
                            }
                            .frame(height: 40)
                        }
                        .foregroundStyle(.primary)
                        .swipeActions {
                            Button {
                                isQueueing = true
                                Task {
                                    //                                    playHistory.remove(playableContent)
                                    //                                    playHistory.insert(playableContent, at: 0)
                                    await sonosService.queue(playable: playableContent, group: group, position: .next)
                                    self.context?.completeRequest(returningItems: [])
                                }
                            } label: {
                                Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                                    .font(.caption)
                            }
                        }
                    }
                    .listRowSpacing(10)
                    .disabled(isQueueing)
                }
            }
            .overlay {
                if isQueueing {
                    ProgressView()
                        .background {
                            Circle()
                                .padding()
                                .foregroundStyle(.thinMaterial)
                        }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        self.context?.completeRequest(returningItems: [])
                    }
                }
            }
        }
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
            impactFeedbackGenerator.prepare()
        }
        .onChange(of: viewModel.url) {
            Task {
                guard let url = viewModel.url, let playableContent = await sonosService.getContent(from: url) else {
                    viewModel.isLoading = false
                    return
                }
                self.playableContent = playableContent
                viewModel.isLoading = false
            }
        }
        .overlay {
            if playableContent == nil, !viewModel.isLoading {
                VStack {
                    Text("Only Apple Music, Spotify, and Tidal Supported")
                        .font(.title)
                        .padding()
                        .multilineTextAlignment(.center)
                    Text("Album, Songs, and Public Playlists.")
                        .multilineTextAlignment(.center)
                }
            }
            if playableContent != nil, sonosService.groups.isEmpty {
                Text("No system available")
                    .font(.title)
                    .padding()
                    .multilineTextAlignment(.center)
            }
            if viewModel.isLoading {
                ProgressView()
            }
        }
    }

    @Observable
    final class ViewModel {
        var url: URL?
        var isLoading: Bool = true
    }
}


