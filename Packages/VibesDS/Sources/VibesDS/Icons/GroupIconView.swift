import SwiftUI


public struct GroupIconView: View {
    public init() { }
    
    public var body: some View {
        Image("hifispeaker.arrow.forward.fill")
            .symbolRenderingMode(.monochrome)
            .frame(width: 24)
            .accessibilityLabel("Group Speakers")
    }
}


#Preview {
    GroupIconView()
}

