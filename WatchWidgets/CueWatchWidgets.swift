import AppIntents
import SwiftUI
import WatchSync
import WidgetKit

/// Cue on the watch face, in the Smart Stack and in Control Center: what's
/// playing or what's on the watch, with a button to shuffle it, and a
/// Shuffle Downloads control. The watch app keeps the state they show
/// (`WatchWidgetState`) and reloads them when it changes; their buttons run
/// the app's playback intents, which play in the app.
@main
struct CueWatchWidgets: WidgetBundle {
    var body: some Widget {
        CueWidget()
        if #available(watchOS 26.0, *) {
            ShuffleDownloadsControl()
        }
    }
}

struct CueWidgetEntry: TimelineEntry {
    let date: Date
    let state: WatchWidgetState

    /// Up the Smart Stack while music plays, or while songs are still to
    /// come down.
    var relevance: TimelineEntryRelevance? {
        if state.isPlaying { return TimelineEntryRelevance(score: 100) }
        if state.songsToDownload > 0 { return TimelineEntryRelevance(score: 40) }
        return TimelineEntryRelevance(score: 5)
    }
}

struct CueWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> CueWidgetEntry {
        CueWidgetEntry(date: .now, state: .preview)
    }

    func getSnapshot(in context: Context, completion: @escaping (CueWidgetEntry) -> Void) {
        completion(entry(in: context))
    }

    /// One entry, kept until the app says something changed.
    func getTimeline(in context: Context, completion: @escaping (Timeline<CueWidgetEntry>) -> Void) {
        completion(Timeline(entries: [entry(in: context)], policy: .never))
    }

    private func entry(in context: Context) -> CueWidgetEntry {
        CueWidgetEntry(date: .now, state: context.isPreview ? .preview : .load())
    }
}

struct CueWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "CueWatch", provider: CueWidgetProvider()) { entry in
            CueWidgetView(entry: entry)
        }
        .configurationDisplayName("Cue")
        .description("What's playing, and the music on your watch.")
        .supportedFamilies([.accessoryRectangular, .accessoryCircular, .accessoryCorner, .accessoryInline])
    }
}

struct CueWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: CueWidgetEntry

    private var state: WatchWidgetState { entry.state }

    var body: some View {
        content
            .widgetURL(URL(string: state.nowPlayingTitle == nil ? "cuewatch://downloads" : "cuewatch://nowplaying"))
            .containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryRectangular:
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 1) {
                    Label("Cue", systemImage: state.isPlaying ? "waveform" : "music.note")
                        .font(.headline)
                        .widgetAccentable()
                    Text(headline)
                        .lineLimit(1)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if state.songsOnWatch > 0, state.nowPlayingTitle == nil {
                    Button(intent: ShuffleDownloadsIntent()) {
                        Image(systemName: "shuffle")
                    }
                    .accessibilityLabel("Shuffle Downloads")
                }
            }
        case .accessoryCircular:
            ZStack {
                AccessoryWidgetBackground()
                VStack(spacing: 0) {
                    Image(systemName: state.isPlaying ? "waveform" : "music.note")
                    Text("\(state.songsOnWatch)")
                        .font(.footnote)
                        .monospacedDigit()
                }
            }
        case .accessoryCorner:
            Image(systemName: state.isPlaying ? "waveform" : "music.note")
                .font(.title3)
                .widgetLabel {
                    Text(songCount)
                }
        default:
            Text(state.nowPlayingTitle ?? "Cue • \(songCount)")
        }
    }

    private var songCount: String {
        state.songsOnWatch == 1 ? "1 song" : "\(state.songsOnWatch) songs"
    }

    private var headline: String {
        state.nowPlayingTitle ?? (state.songsOnWatch == 0 ? "No music yet" : "\(songCount) on watch")
    }

    private var detail: String {
        if let artist = state.nowPlayingArtist, state.nowPlayingTitle != nil {
            return artist
        }
        if state.songsToDownload > 0 {
            return "\(state.songsToDownload) to download"
        }
        return state.songsOnWatch == 0
            ? "Browse your library in Cue"
            : ByteCountFormatter.string(fromByteCount: state.bytesUsed, countStyle: .file)
    }
}

/// Control Center's Shuffle Downloads button (watchOS 26).
@available(watchOS 26.0, *)
struct ShuffleDownloadsControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "dance.cue.watch.shuffle-downloads") {
            ControlWidgetButton(action: ShuffleDownloadsIntent()) {
                Label("Shuffle Downloads", systemImage: "shuffle")
            }
        }
        .displayName("Shuffle Downloads")
        .description("Shuffles the music on your Apple Watch.")
    }
}

extension WatchWidgetState {
    /// What the widget gallery shows.
    static let preview = WatchWidgetState(songsOnWatch: 124, songsToDownload: 0, bytesUsed: 1_020_000_000)
}
