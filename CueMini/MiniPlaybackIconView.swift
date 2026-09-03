//
//  PlaybackIconView.swift
//  Cue
//
//  Created by Nick Hayward on 9/24/25.
//


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
        VibeMiniGaugeView(value: value, total: total, color: isPlaying ? Color.primary : Color.secondary, lineWidth: 2.5)
            .overlay(alignment: .center) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(isPlaying ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary))
                    .contentTransition(.symbolEffect(.replace))
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
        
        Slider(value: $value, in: 0...100)
    }
    .animation(.interactiveSpring, value: value)
}

public struct VibeMiniGaugeView: View {
    var value: Double
    var total: Double
    var color: Color
    var lineWidth: CGFloat = 2
    
    public init(value: Double, total: Double, color: Color, lineWidth: CGFloat) {
        self.value = value
        self.total = total
        self.color = color
        self.lineWidth = lineWidth
    }
    
    public var body: some View {
        ZStack {
            Circle()
                .stroke(
                    color.secondary.opacity(0.4),
                    lineWidth: lineWidth
                )
            if value > 0 && total > 0 {
                Circle()
                    .trim(from: 0, to: CGFloat(min(value/total, 1.0)))
                    .stroke(
                        color,
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            lineCap: .round
                        )
                    )
                    .rotationEffect(.degrees(-90))
                    .animation(.spring, value: value)
            }
        }
    }
}
