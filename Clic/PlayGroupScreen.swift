import SwiftUI
import SonosKit
import VibesDS

struct PlayGroupScreen: View {
    @Environment(\.dismiss) private var dismiss

    @Environment(SonosService.self) var sonosService: SonosService
//    @State var playableContent: PlayableContent

    private let impactFeedbackGenerator = UIImpactFeedbackGenerator()

    var body: some View {
        @Bindable var sonosService = sonosService
        NavigationStack {
            VStack {

//                HStack(alignment: .top) {
//                    AsyncImage(url: playableContent.artwork) { image in
//                        image
//                            .resizable()
//                            .clipShape(RoundedRectangle(cornerRadius: 4))
//                    } placeholder: {
//                        ProgressView() // Displays a progress indicator while the image is loading
//                    }
//                    .transition(.scale)
//                    .aspectRatio(contentMode: .fill) // Maintains the aspect ratio of the image
//                    .frame(width: 100, height: 100)
//                    VStack(alignment: .leading) {
//                        Text(playableContent.title)
//                        Text(playableContent.subtitle)
//                            .foregroundStyle(.secondary)
//                    }
//                    .frame(maxWidth: .infinity, alignment: .leading)
//                    .fontDesign(.rounded)
//                }
//                .padding(.horizontal)

                List(sonosService.sorted) { group in
                    VStack(alignment: .leading) {
                        Button {
                            impactFeedbackGenerator.impactOccurred()
                            Task {
//                                guard let url = playableContent.content.location else { return }
//                                await sonosService.queue(url: url, group: group)
//                                await sonosService.play(ip: group.ip)
                            }
                        } label: {
                            Text(group.nameWithCount)
                                .fontDesign(.rounded)
                                .bold()
                        }
                    }
                    .foregroundStyle(.primary)
                    .swipeActions {
                        Button {
                            dismiss()
                            Task {
//                                guard let url = playableContent.content.location else { return }
//                                await sonosService.queue(url: url, group: group, position: .next)
                            }
                        } label: {
                            Label("Play Next", systemImage: "text.line.last.and.arrowtriangle.forward")
                                .font(.caption)
                        }
                    }
                }
                .listRowSpacing(10)
            }
            //            .toolbar {
            //                ToolbarItem(placement: .topBarTrailing) {
            //                    Button("Done") {
            //                        dismiss()
            //                    }
            //                }
            //            }
        }
        .task {
            try? await sonosService.updateGroups()
            try? await sonosService.load(useCache: true)
            impactFeedbackGenerator.prepare()
        }
    }
}


#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            PlayGroupScreen()
                .environment(SonosService.shared)
        }
}
