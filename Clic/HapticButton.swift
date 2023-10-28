import SwiftUI

struct Test: View {
    let feedback: SensoryFeedback
    let action: () -> Void
    @State var trigger: Bool = false

    var body: some View {
        Button {
            trigger.toggle()
            action()
        } label: {

        }
        .buttonStyle(.haptic)
    }
}


struct HapticButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration
            .label
            .sensoryFeedback(.selection, trigger: configuration.isPressed == true)
    }
}

//extension PrimitiveButtonStyle where Self == HapticButtonStyle {
//
//    /// A button style that applies standard border artwork based on the
//    /// button's context.
//    ///
//    /// To apply this style to a button, or to a view that contains buttons, use
//    /// the ``View/buttonStyle(_:)-66fbx`` modifier.
//    public static var hapticButtonStyle: HapticButtonStyle { get }
//}

extension ButtonStyle where Self == HapticButtonStyle {
    static var haptic: HapticButtonStyle {
        HapticButtonStyle()
    }
}
