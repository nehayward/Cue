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

    var body: some View {
        if !items.isEmpty {
            LazyVGrid(columns: [.init(), .init()]) {
                ForEach(items.prefix(limit)) { item in
                    PlayableContentRowView(item: item)
                        .buttonStyle(.plain)
                        .geometryGroup()
                }
            }
        }
    }
}
