//
//  PlaybackIconView.swift
//  Clic
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
        if #available(iOS 26.0, watchOS 26.0, macOS 26, *) {
            Image(systemName: isPlaying ? "pause.circle" : "play.circle", variableValue: value/total)
                .contentTransition(.symbolEffect(.automatic))
                .symbolVariableValueMode(.draw)
                .foregroundStyle(isPlaying ? Color.primary : .secondary, isPlaying ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary))
                .font(.title)
        } else {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(isPlaying ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(Color.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 16, height: 16, alignment: .center)
        }
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

