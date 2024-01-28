import CloudStorage
import SwiftUI
import SonosKit
import NukeUI

public struct SceneButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .bold()
            .fontDesign(.rounded)
            #if !os(visionOS)
            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
            #endif
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background{
                Capsule()
                    .modifier(SceneButtonForegroundColor())
                    .shadow(radius: 2, x: 0, y: 1)
            }
            .offset(y: configuration.isPressed ? 2 : 0)
            .animation(.default, value: configuration.isPressed)
    }
}

struct SceneButtonForegroundColor: ViewModifier {
    func body(content: Content) -> some View {
#if os(watchOS)
        return content.foregroundStyle(.fill)
#else
        return content.foregroundStyle(.ultraThickMaterial)
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
            VStack {
                Text(scene.name)
                    .frame(maxWidth: .infinity)
                    .fontDesign(.rounded)
                    .bold()
                    .padding()
            }
        }
        .overlay(alignment: .leading) {
            if let artworkURL {
                LazyImage(url: artworkURL) { state in
                    if let image = state.image {
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .foregroundStyle(.thinMaterial)
                            .frame(width: 50, height: 50)
                    }
                }
                .padding()
            }
        }
        .overlay {
            ZStack {
                Capsule()
                    .inset(by: 4)
                    .trim(from: 0, to: 1)
                    .stroke(Color.accentColor.gradient, lineWidth: 3)
                    .opacity(started ? 0.4 : 0)
                Capsule()
                    .inset(by: 4)
                    .trim(from: 0, to: started ? 1 : 0)
                    .stroke(Color.accentColor.gradient, style: .init(lineWidth: 4, lineCap: started ? .round : .butt))
                    .rotationEffect(.degrees(-180))
            }
            .onChange(of: started) { oldValue, newValue in
                if oldValue == newValue { return }
                if newValue {
                    Task {
                        try? await Task.sleep(for: .seconds(2))
                        started = false
                    }
                }
            }
        }
        .animation(started ? .snappy : nil, value: started)
        .task {
            if let content = scene.playableContent {
                artworkURL = await SonosService.shared.getArtwork(from: content.content)
            }
        }
        .buttonBorderShape(.capsule)
        .background(.thinMaterial)
        .clipShape(Capsule())
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
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10)],
                        playableContent: PlayableContent(title: "One Night/All Night", subtitle: "Justice", artwork: nil, content: MediaContent(service: .spotify, id: "7sjuNUjWtSqhbxJ3RAUffm", type: .track, location: nil))
                    )
            ) {
                print("HERE")
            }
            SceneButton(
                scene:
                    SonosScene(
                        id: UUID(),
                        name: "Main",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
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
                        name: "Theater + Kitchen",
                        rooms: [SceneRoom(id: "", ip: "", name: "Gym", volume: 10),
                                SceneRoom(id: "", ip: "", name: "Gym", volume: 10)],
                        playableContent: PlayableContent(title: "One Night/All Night", subtitle: "Justice", artwork: nil, content: MediaContent(service: .spotify, id: "7sjuNUjWtSqhbxJ3RAUffm", type: .track, location: nil))
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
                        playableContent: PlayableContent(title: "One Night/All Night", subtitle: "Justice", artwork: nil, content: MediaContent(service: .spotify, id: "7sjuNUjWtSqhbxJ3RAUffm", type: .track, location: nil))
                    )
            ) {
                print("HERE")
            }
        }
    }
}
