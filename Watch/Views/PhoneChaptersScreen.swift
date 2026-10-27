import SwiftUI
import WatchKit
import WatchSync

/// The chapters of the book the iPhone plays (`PhoneNowPlaying.chapters`),
/// opened from the top right of its player: the one playing in the tint,
/// filled behind as far as it's been heard, and scrolled to; the ones
/// before it dimmed; each with its length. A tap plays the book there from
/// that chapter's start and goes back to the player. Asked for as it opens.
struct PhoneChaptersScreen: View {
    @Environment(PhoneNowPlaying.self) private var phone
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack {
            if phone.current == nil {
                Text(phone.isPhoneInReach ? "Nothing playing on iPhone" : "iPhone out of reach")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            } else if let chapters = phone.chapters {
                if chapters.chapters.isEmpty {
                    Text("No chapters")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                } else {
                    list(chapters.chapters)
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Chapters")
        .containerBackground(for: .navigation) {
            ImageMeshFill(image: phone.artwork)
        }
        .task(id: phone.current?.bookKey) {
            phone.refreshChapters()
        }
    }

    private func list(_ chapters: [WatchPhoneChapters.Chapter]) -> some View {
        let playing = phone.current?.chapterID
        let clock = phone.current.flatMap { now in
            now.barLength.map { PlayerClock(elapsed: now.elapsed(at: .now) ?? 0, duration: $0, at: .now, rate: now.rate, isPlaying: now.isPlaying) }
        }
        return ScrollViewReader { proxy in
            List(chapters) { chapter in
                Button {
                    WKInterfaceDevice.current().play(.click)
                    phone.playChapter(chapter)
                    dismiss()
                } label: {
                    HStack(spacing: 6) {
                        VStack(alignment: .leading) {
                            Text(chapter.title)
                                .lineLimit(2)
                                .foregroundStyle(chapter.id == playing ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary.opacity(chapter.id < playing ?? 0 ? 0.6 : 1)))
                            Text(WatchBookFormat.length(chapter.duration))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        if chapter.id == playing {
                            Image(systemName: "waveform")
                                .font(.footnote)
                                .foregroundStyle(.tint)
                                .symbolEffect(.variableColor.iterative, isActive: phone.current?.isPlaying == true)
                                .accessibilityLabel(phone.current?.isPlaying == true ? "Playing" : "Paused")
                        }
                    }
                }
                .id(chapter.id)
                .listRowBackground(chapter.id == playing ? clock.map(ChapterRowFill.init) : nil)
            }
            .onAppear {
                if let playing {
                    proxy.scrollTo(playing, anchor: .center)
                }
            }
        }
    }
}
