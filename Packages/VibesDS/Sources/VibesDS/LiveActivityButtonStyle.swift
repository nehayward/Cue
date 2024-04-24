import CloudStorage
import SwiftUI
import SonosKit
import NukeUI

public struct LiveActivityButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .bold()
            .fontDesign(.rounded)
            #if !os(visionOS)
            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
            #endif
            .padding(12)
            .background{
                Circle()
                    .foregroundStyle(.quaternary.opacity(configuration.isPressed ? 1 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.85 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.default, value: configuration.isPressed)

    }
}


public extension ButtonStyle where Self == LiveActivityButtonStyle {
   static var liveActivity: LiveActivityButtonStyle {
       LiveActivityButtonStyle()
    }
}

#Preview {
    Button {

    } label: {
        Image(systemName: "plus")
    }
    .tint(.red)
    .buttonStyle(.liveActivity)
}
