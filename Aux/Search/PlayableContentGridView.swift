//
//  PlayableContentGridView.swift
//  Clic
//
//  Created by Nick Hayward on 6/17/26.
//
import SonosKit
import SwiftUI

struct PlayableContentGridView: View {
    let items: [PlayableContent]
    var limit: Int = 7

    /// `.adaptive`, deliberately, rather than measuring the width and choosing
    /// a column count from `@State`. These rows sit in self-sizing `List`
    /// cells, and feeding a measurement back into the layout that produced it
    /// closes a loop — width → column count → row height → content size →
    /// width — which UIKit kills the app over ("stuck in a recursive layout
    /// loop"). `.adaptive` is resolved by the grid from the width it is
    /// offered, with no state round-trip.
    ///
    /// 360pt is the narrowest a column can be before ordinary album titles
    /// truncate next to their artwork; the count follows from the width, so
    /// this is two columns where it always was and three or more once there's
    /// room.
    private static let columns = [GridItem(.adaptive(minimum: 360), spacing: 12)]

    var body: some View {
        if !items.isEmpty {
            LazyVGrid(columns: Self.columns) {
                ForEach(items.prefix(limit)) { item in
                    PlayableContentRowView(item: item)
                        .buttonStyle(.plain)
                        .geometryGroup()
                }
            }
        }
    }
}
