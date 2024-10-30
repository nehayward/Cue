import CloudStorage
import SwiftUI
import SonosKit
import NukeUI

public struct SceneButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .fontDesign(.rounded)
            #if !os(visionOS)
            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
            #endif
            .padding(.horizontal, 8)
            .background{
                Capsule()
                    .foregroundStyle(.background.secondary)
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.default, value: configuration.isPressed)
            .shadow(radius: 1)
    }
}

struct SceneButtonForegroundColor: ViewModifier {
    func body(content: Content) -> some View {
#if os(watchOS)
        return content.foregroundStyle(.fill)
#else
        return content.foregroundStyle(.fill)
#endif
    }
}

public extension ButtonStyle where Self == SceneButtonStyle {
   static var scene: SceneButtonStyle {
        SceneButtonStyle()
    }
}

public struct SceneButton: View {
    public var scene: SonosScene
    public var action: () -> Void

    @State private var started: Bool = false
    @State private var artworkURL: URL?

    public init(scene: SonosScene, action: @escaping () -> Void) {
        self.scene = scene
        self.action = action
    }

    public var body: some View {
        Button {
            action()
            started = true
        } label: {
            VStack(spacing: 0) {
                Text(scene.name)
                    .lineLimit(1)
                    .frame(maxWidth: 260)
                    .fontDesign(.rounded)
                    .multilineTextAlignment(.center)
            }
            .padding()
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.scene)
//        .overlay(alignment: .leading) {
//            if let artworkURL {
//                LazyImage(url: artworkURL) { state in
//                    if let image = state.image {
//                        image
//                            .resizable()
//                            .aspectRatio(contentMode: .fit)
//                            .frame(width: 50, height: 50)
//                            .clipShape(Circle())
//                    } else {
//                        Circle()
//                            .foregroundStyle(.thinMaterial)
//                            .frame(width: 50, height: 50)
//                    }
//                }
//                .padding()
//            }
//        }
//        .overlay(alignment: .trailing) {
//            ZStack {
//                ForEach(Array(scene.rooms.enumerated()), id: \.offset) { index, room in
//                    VibeGaugeView(
//                        value: room.volume,
//                        total: 100,
//                        color: .primary,
//                        lineWidth: 2
//                    )
//                    .frame(width: CGFloat(50 - (index * 8)), height: CGFloat(50 - (index * 8))) // Decrease size by 4 for each index
//                }
//            }
//            .padding()
//        }
        .task {
            if let content = scene.playableContent {
                artworkURL = await SonosService.shared.getArtwork(from: content)
            }
        }
    }
}

#Preview {
    ScrollView {
        VStack {
            SceneButton(
                scene:
                    SonosScene(
                        id: UUID(),
                        name: "Living Room",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Garage", volume: 10)],
                        playableContent: PlayableContent(title: "One Night/All Night", subtitle: "Justice", thumbnail: nil, artwork: nil, content: MediaContent(service: .spotify, id: "7sjuNUjWtSqhbxJ3RAUffm", type: .track, location: nil))
                    )
            ) {
                print("HERE")
            }
            SceneButton(
                scene:
                    SonosScene(
                        id: UUID(),
                        name: "Main",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 100),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 12),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 12),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 12),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10),SceneRoom(id: "", ip: "", name: "Gym", volume: 10)]
                    )
            ) {
                print("HERE")
            }

            SceneButton(
                scene:
                    SonosScene(
                        id: UUID(),
                        name: "Theater + Kitchen + Theater + Living Room",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10)],
                        playableContent: PlayableContent(title: "One Night/All Night", subtitle: "Justice", thumbnail: nil, artwork: nil, content: MediaContent(service: .spotify, id: "7sjuNUjWtSqhbxJ3RAUffm", type: .track, location: nil))
                    )
            ) {
                print("HERE")
            }

            SceneButton(
                scene:
                    SonosScene(
                        id: UUID(),
                        name: "Living Room",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10)],
                        playableContent: PlayableContent(
                            title: "Cold Heart - PNAU Remix",
                            subtitle: "Elton John, Dua Lipa, PNAU",
                            thumbnail: URL(
                                string: "https://i.scdn.co/image/ab67616d00004851523458c391fe8180a19a1069"
                            ),
                            artwork: URL(
                                string: "https://i.scdn.co/image/ab67616d0000b273523458c391fe8180a19a1069"
                            ),
                            content: MediaContent(service: MusicService.spotify, id: "7rglLriMNBPAyuJOMGwi39", type: .track, location: URL(string:"https://open.spotify.com/track/7rglLriMNBPAyuJOMGwi39"))
                        )
                    )
            ) {
                print("HERE")
            }
        }
    }
}
