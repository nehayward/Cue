//

import SwiftUI

struct ContentView: View {

    @State var items = Array(0...200)
    @State var value = 0.0
    @State private var animateGradient = false

    private var features = [
        (Icons.speaker.systemName, "Show All Devices", "Effortlessly manage all your Sonos devices in one place."),
        (Icons.liveActivity.systemName, "Live Activities + Dynamic Island", "Instantly adjust playback and volume from the lock screen."),
        (Icons.widgets.systemName, "Interactive Widgets", "Convenient home screen widgets for immediate playback control."),
        (Icons.watch.systemName, "Apple Watch", "Control your Sonos system with ease from your wrist."),
        (Icons.scenes.systemName, "Scenes", "Group rooms and set ideal volume with a single tap."),
        (Icons.shortcuts.systemName, "Apple Shortcuts", "Rapidly manage playback using the Shortcuts app.")
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Clic Super")
                    .bold()
                    .font(.largeTitle)
                    .foregroundStyle(.teal.gradient)
                    .onAppear {
                        withAnimation(.smooth(duration: 5).repeatForever(autoreverses: true)) {
                            animateGradient.toggle()
                        }
                    }
                    .padding(.bottom, 24)
                ForEach(Array(features.enumerated()), id: \.offset) { index, element in
                    HStack(alignment: .top) {
                        Image(systemName: element.0)
                            .foregroundStyle(.teal.gradient)
                        VStack(alignment: .leading) {
                            Text(element.1)
                                .bold()
                                .font(.title3)
                                .foregroundStyle(.teal.gradient)
                            Text(element.2)
                                .lineLimit(2, reservesSpace: true)
                                .foregroundStyle(.primary.opacity(0.6))
                        }
                        Spacer()
                    }
                    .frame(maxWidth: 500)
                    .padding(.horizontal)
                }
            }
            .fontDesign(.rounded)
            .saturation(animateGradient ? 1 : 3)
        }
        .background {
            LinearGradient(colors: [.teal.opacity(0.3), .teal.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
          //                    .blendMode(.darken)
//            ZStack {
//                Color.teal
//                LinearGradient(colors: [.teal, .black], startPoint: .topLeading, endPoint: .bottomTrailing)
//                    .blendMode(.darken)
//
//            }
//                .ignoresSafeArea()
//                .opacity(0.4)
//                .blur(radius: 10)
//            LinearGradient(colors: [.teal, Color(uiColor: .black)], startPoint: animateGradient ? .topLeading : .bottomLeading, endPoint: animateGradient ? .bottomTrailing : .topTrailing)
//                .saturation(animateGradient ? 0.5 : 2)
////                .hueRotation(.degrees(animateGradient ? 30 : 0))
//                .onAppear {
//        //            withAnimation(.spring(duration: 100)) {
//        //                value = 1000
//        //            }
//                    withAnimation(.easeInOut(duration: 10.0).repeatForever(autoreverses: true)) {
//                        animateGradient.toggle()
//                    }
//                }
//                .ignoresSafeArea()
        }


//        .onAppear {
////            withAnimation(.spring(duration: 100)) {
////                value = 1000
////            }
//            withAnimation(.easeInOut(duration: 2).repeatForever(autoreverses: true)) {
//                animateGradient.toggle()
//            }
//        }

//            .overlay {
//
//            }
    }
}

#Preview {
    ContentView()
}

fileprivate enum Icons {
    case watch
    case speaker
    case shortcuts
    case widgets
    case liveActivity
    case scenes

    init(number: Int) {
        let option = number % 6
        switch option {
        case 0:
            self = .watch
        case 1:
            self = .speaker
        case 2:
            self = .shortcuts
        case 3:
            self = .widgets
        case 4:
            self = .liveActivity
        case 5:
            self = .scenes
        default:
            self = .watch
        }
    }

    var systemName: String {
        switch self {
        case .watch:
            return "applewatch"
        case .speaker:
            return "hifispeaker.2.fill"
        case .shortcuts:
            return "point.topleft.down.to.point.bottomright.curvepath.fill"
        case .widgets:
            return "square.stack"
        case .scenes:
            return "bolt.fill"
        case .liveActivity:
            return "dot.radiowaves.left.and.right"
        }
    }
}
