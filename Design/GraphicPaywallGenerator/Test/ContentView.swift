//

import SwiftUI

struct ContentView: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns:  [
                GridItem(.adaptive(minimum: 80, maximum: 80))
            ], spacing: 50) {
                ForEach(0...1000, id: \.self) { number in
                    VStack {
                        Image(systemName: Icons(number: number).systemName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 50, height: 50)
//                            .rotationEffect(.degrees(-45))
                    }
                }
            }
            .ignoresSafeArea()
        }
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

    init(number: Int) {
        let option = number % 4
        switch option {
        case 0:
            self = .watch
        case 1:
            self = .speaker
        case 2:
            self = .shortcuts
        case 3:
            self = .widgets
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
        }
    }
}
