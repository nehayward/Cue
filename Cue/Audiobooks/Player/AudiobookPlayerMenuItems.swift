import Defaults
import MusicSearchKit
import SonosKit
import SwiftUI

/// The player menu's book items while a book plays: Previous and Next
/// Chapter, the chapters sheet, and on this device its speed (a speaker has
/// only 1×).
struct AudiobookPlayerMenuItems: View {
    let isOnDevice: Bool

    @Environment(Router.self) private var router
    @State private var player = AudiobookPlayer.shared

    var body: some View {
        if let book = player.current {
            if book.chapters.count > 1 {
                ControlGroup {
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        Task { await player.skipToPreviousChapter() }
                    } label: {
                        Label("Previous Chapter", systemImage: "backward.end.fill")
                    }
                    Button {
                        HapticManager.shared.fireHaptic(.selection)
                        Task { await player.skipToNextChapter() }
                    } label: {
                        Label("Next Chapter", systemImage: "forward.end.fill")
                    }
                    .disabled(player.nextChapter == nil)
                }
                Button {
                    router.sheet(to: .audiobookChapters)
                } label: {
                    Label(player.currentChapter?.title ?? "Chapters", systemImage: "list.bullet")
                }
            }
            if isOnDevice {
                Picker(selection: Binding(get: { player.rate }, set: { player.setRate($0) })) {
                    ForEach(AudiobookPlayer.rates, id: \.self) { rate in
                        Text(Self.label(for: rate)).tag(rate)
                    }
                } label: {
                    Label("Speed", systemImage: "gauge.with.dots.needle.67percent")
                    Text(Self.label(for: player.rate))
                }
                .pickerStyle(.menu)
            }
        }
    }

    /// "1.25×".
    static func label(for rate: Double) -> String {
        rate.formatted(.number.precision(.fractionLength(0...2))) + "×"
    }
}
