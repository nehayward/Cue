//
//  View+Debug.swift
//  Cue
//
//  Created by Nick Hayward on 3/13/26.
//
import SwiftUI

#if DEBUG
extension View {
    func debugBackground() -> some View {
        background(Color.random())
    }
}

public extension Color {
    static func random(randomOpacity: Bool = false) -> Color {
        Color(
            red: .random(in: 0...1),
            green: .random(in: 0...1),
            blue: .random(in: 0...1),
            opacity: randomOpacity ? .random(in: 0...1) : 1
        )
    }
}
#endif
