#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

struct LiveActivityNowPlaying: View {
    var context: ActivityViewContext<CueNowPlayingWidgetAttributes>
    var body: some View {
        if #available(iOS 18.0, *) {
            LiveActivityNowPlayingFamilyView(context: context)
        } else {
            LiveActivityNowPlayingView(context: context)
        }
    }
}


extension CueNowPlayingWidgetAttributes {
    fileprivate static var preview: CueNowPlayingWidgetAttributes {
        CueNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Gym"))
    }
}

extension CueNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: CueNowPlayingWidgetAttributes.ContentState {
        CueNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa", thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 39,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: false
        )
    }

    fileprivate static var testing2: CueNowPlayingWidgetAttributes.ContentState {
        CueNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa",  thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 50,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: false
        )
    }

    fileprivate static var theater: CueNowPlayingWidgetAttributes.ContentState {
        CueNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa",  thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 50,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: true,
            TVSettings: .init(nightMode: false, dialogLevel: true, audioInputFormat: .dolbyAtmosDDPlus)
        )
    }
}

#Preview("Lock Screen", as: .content, using: CueNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    CueNowPlayingWidgetAttributes.ContentState.testing
    CueNowPlayingWidgetAttributes.ContentState.theater
}

#Preview("Lock Screen 2", as: .content, using: CueNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    CueNowPlayingWidgetAttributes.ContentState.testing2
}

#Preview("Lock Screen Compact", as: .content, using: CueNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    CueNowPlayingWidgetAttributes.ContentState.testing2
}
#endif
