import SwiftUI


public struct PlaybackIconView: View {
    var value: Double
    var total: Double
    var isPlaying: Bool
    
    public init(value: Double, total: Double, isPlaying: Bool) {
        self.value = value
        self.total = total
        self.isPlaying = isPlaying
    }
    
    public var body: some View {
        VibeGaugeView(value: value, total: total, color: .primary, lineWidth: 2)
            .overlay(alignment: .center) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isPlaying ? Color.primary : Color.secondary)
                    .contentTransition(.symbolEffect(.automatic))
                    .frame(width: 12, height: 12, alignment: .center)
                    .padding(.leading, !isPlaying ? 2 : 0)
            }
            .frame(width: 24, height: 24)
    }
}


#Preview {
    PlaybackIconView(value: 12, total: 100, isPlaying: true)
}

