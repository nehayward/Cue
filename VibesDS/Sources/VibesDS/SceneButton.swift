import CloudStorage
import SwiftUI
import SonosKit

public struct SceneButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .bold()
            .fontDesign(.rounded)
            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
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
    @Binding public var scene: SonosScene
    public var action: () -> Void

    @State private var started: Bool = false

    public init(scene: Binding<SonosScene>, action: @escaping () -> Void) {
        self._scene = scene
        self.action = action
    }

    public var body: some View {
        Button {
            action()
            started = true
        } label: {
            Text(scene.name)
        }
        .buttonStyle(.scene)
        .overlay {
            ZStack {
                Capsule()
                    .trim(from: 0, to: 1)
                    .stroke(Color.accentColor.gradient, lineWidth: 3)
                    .opacity(started ? 0.4 : 0)
                Capsule()
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
                        print("Done")
                    }
                }
            }
        }
        .animation(started ? .snappy : nil, value: started)

    }
}

#Preview {
    HStack {
        SceneButton(
            scene: .constant(
                SonosScene(
                    id: UUID(),
                    name: "Main",
                    rooms: [SceneRoom(id: "", ip: "", name: "Main", volume: 10)]
                )
            )
        ) {
            print("HERE")
        }
        SceneButton(
            scene: .constant(
                SonosScene(
                    id: UUID(),
                    name: "Main",
                    rooms: [SceneRoom(id: "", ip: "", name: "Main", volume: 10)]
                )
            )
        ) {
            print("HERE")
        }
    }
}
