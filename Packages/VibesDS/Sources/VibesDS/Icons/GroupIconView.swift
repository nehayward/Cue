import SwiftUI


public struct GroupIconView: View { 
    private var speakerSymbolName: String {
        "hifispeaker.arrow.forward.fill"
    }
    
    public init() { }
    
    public var body: some View {
        Image(speakerSymbolName)
            .symbolRenderingMode(.monochrome)
            .frame(width: 24)
            .accessibilityLabel("Group Speakers")
    }
}


#Preview {
    GroupIconView()
}

