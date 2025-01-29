import CloudStorage
import SwiftUI
import SonosKit

public struct LiveActivityButtonStyle: ButtonStyle {
    public func makeBody(configuration: Configuration) -> some View {
        LiveActivityButton(configuration: configuration)
    }

    struct LiveActivityButton: View {
        @Environment(\.isEnabled) private var isEnabled: Bool
        let configuration: ButtonStyle.Configuration
        @State private var isAnimatingPress: Bool = false

        var body: some View {
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
                       .foregroundStyle(.quaternary.opacity(isAnimatingPress ? 1 : 0))
               }
               .scaleEffect(isAnimatingPress ? 0.85 : 1)
               .opacity(isAnimatingPress ? 0.8 : 1)
               .animation(.default, value: isAnimatingPress)
               .opacity(isEnabled ? 1.0 : 0.4)
               .contentShape(Circle())
               .onChange(of: configuration.isPressed) { wasPressed, isPressed in
                    if isPressed {
                        isAnimatingPress = true
                    } else {
                        // Add a slight delay before releasing the animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            withAnimation {
                                isAnimatingPress = false
                            }
                        }
                    }
               }
        }
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
