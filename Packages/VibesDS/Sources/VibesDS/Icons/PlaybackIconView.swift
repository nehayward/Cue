import SwiftUI


public struct PlaybackIconView: View {
    var value: Double
    var total: Double
    var isPlaying: Bool
    var isTransitioning: Bool

    public init(value: Double, total: Double, isPlaying: Bool, isTransitioning: Bool = false) {
        self.value = value
        self.total = total
        self.isPlaying = isPlaying
        self.isTransitioning = isTransitioning
    }

    public var body: some View {
        VibeGaugeView(value: value, total: total, color: isPlaying ? Color.primary : Color.secondary, lineWidth: 2.5)
            .overlay(alignment: .center) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isPlaying ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
                    .symbolEffect(.pulse, isActive: isTransitioning)
                    .frame(width: 12, height: 12, alignment: .center)
                    .padding(.leading, !isPlaying ? 2 : 0)
            }
            .frame(width: 24, height: 24)
    }
}

#Preview {
    @Previewable @State var isPlaying: Bool = true
    @Previewable @State var value: Double = 0

    VStack {
        PlaybackIconView(value: value, total: 100, isPlaying: isPlaying)
        PlaybackIconView(value: value, total: 100, isPlaying: isPlaying)
            .font(.largeTitle)
        
        Toggle(isOn: $isPlaying) {
            Text("Here")
        }
        
        #if !os(tvOS)
        Slider(value: $value, in: 0...100)
        #endif
    }
    .animation(.interactiveSpring, value: value)
}

