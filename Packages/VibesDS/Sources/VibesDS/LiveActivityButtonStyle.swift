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
                    isAnimatingPress = isPressed
               }
               // Use task modifier with id to automatically cancel when isPressed changes
               .task(id: configuration.isPressed) {
                   // Only run the delay when button is released (not pressed)
                   guard !configuration.isPressed else { return }
                   try? await Task.sleep(for: .milliseconds(100))
                   // This will be automatically cancelled if isPressed changes
                   withAnimation {
                       isAnimatingPress = false
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
