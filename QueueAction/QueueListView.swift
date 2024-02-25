import SwiftUI
import SonosKit
import VibesDS

struct QueueListView: View {
    @Environment(\.dismiss) private var dismiss

    @State var sonosService: SonosService
    @State var playableContent: PlayableContent? = nil
    @State var isQueueing: Bool = false

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
                        } placeholder: {
                            ProgressView() // Displays a progress indicator while the image is loading
                        }
                        .transition(.scale)
                        .aspectRatio(contentMode: .fill) // Maintains the aspect ratio of the image
                        .frame(width: 100, height: 100)
                        VStack(alignment: .leading) {
                            Text(playableContent.title)
                            Text(playableContent.subtitle)
                                .foregroundStyle(.secondary)
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
                                    guard let url = playableContent.content.location else { return }
                                    await sonosService.queue(url: url, group: group)
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
                                dismiss()
                                Task {
                                    guard let url = playableContent.content.location else { return }
                                    await sonosService.queue(url: url, group: group, position: .next)
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
                Text("Only Apple Music and Spotify Supported")
                    .font(.title)
                    .padding()
                    .multilineTextAlignment(.center)
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


