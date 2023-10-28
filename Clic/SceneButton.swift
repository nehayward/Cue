//import CloudStorage
//import SwiftUI
//import SonosKit
//
//struct SceneButtonStyle: ButtonStyle {
//    func makeBody(configuration: Configuration) -> some View {
//        configuration
//            .label
//            .bold()
//            .fontDesign(.rounded)
//            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
//            .padding(.horizontal)
//            .padding(.vertical, 8)
//            .background{
//                Capsule()
//                    .foregroundStyle(.ultraThickMaterial)
//                    .shadow(radius: 2, x: 0, y: 1)
//            }
//            .offset(y: configuration.isPressed ? 2 : 0)
//            .animation(.default, value: configuration.isPressed)
//    }
//}
//
//extension ButtonStyle where Self == SceneButtonStyle {
//    static var scene: SceneButtonStyle {
//        SceneButtonStyle()
//    }
//}
//
//
//
//struct SceneButton: View {
//    @Binding var scene: SonosScene
//    var action: () -> Void
//
//    @State private var started: Bool = false
//
//    var body: some View {
//        Button {
//            action()
//            started = true
//        } label: {
//            Text(scene.name)
//        }
//        .buttonStyle(.scene)
//        .overlay {
//            ZStack {
//                Capsule()
//                    .trim(from: 0, to: 1)
//                    .stroke(Color.accentColor.gradient, lineWidth: 3)
//                    .opacity(started ? 0.4 : 0)
//                Capsule()
//                    .trim(from: 0, to: started ? 1 : 0)
//                    .stroke(Color.accentColor.gradient, style: .init(lineWidth: 4, lineCap: started ? .round : .butt))
//                    .rotationEffect(.degrees(-180))
//            }
//            .onChange(of: started) { oldValue, newValue in
//                if oldValue == newValue { return }
//                if newValue {
//                    Task {
//                        try? await Task.sleep(for: .seconds(2))
//                        started = false
//                        print("Done")
//                    }
//                }
//            }
//
//            //                            .opacity(configuration.isPressed ? 1 : 0)
//        }
//        .animation(started ? .snappy : nil, value: started)
//
//    }
//}
//
//#Preview {
//    Group {
//        SceneButton(
//            scene: .constant(
//                SonosScene(
//                    id: UUID(),
//                    name: "Main",
//                    rooms: [SceneRoom(id: "", ip: "", name: "Main", volume: 10)],
//                    isActive: false
//                )
//            )
//        ) {
//            print("HERE")
//        }
//        SceneButton(
//            scene: .constant(
//                SonosScene(
//                    id: UUID(),
//                    name: "Main",
//                    rooms: [SceneRoom(id: "", ip: "", name: "Main", volume: 10)],
//                    isActive: true
//                )
//            )
//        ) {
//            print("HERE")
//        }
//    }
//}
