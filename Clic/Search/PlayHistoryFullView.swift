import Collections
import CloudStorage
import Defaults
import Foundation
import NukeUI
import SonosKit
import SwiftUI

struct PlayHistoryFullView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(PlayHistoryService.self) private var playHistoryService: PlayHistoryService

    @State private var clearHistoryConfirmation: Bool = false

    var body: some View {
        List {
            ForEach(playHistoryService.history) { item in
                PlayableContentView(item: item)
            }
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                if !playHistoryService.history.isEmpty {
                    Button(role: .destructive) {
                        clearHistoryConfirmation.toggle()
                    } label: {
                        Text("Remove All")
                    }
                }
            }
        }
        .contentMargins(.bottom, 120, for: .scrollContent)
        .navigationTitle("Play History")
        .confirmationDialog("Clear Play History", isPresented: $clearHistoryConfirmation) {
            Button {
                playHistoryService.history.removeAll()
            } label: {
                Text("Remove Play History")
                    .bold()
            }
        }
    }
}
