#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

struct LiveActivityNowPlaying: View {
    var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    var body: some View {
        if #available(iOS 18.0, *) {
            LiveActivityNowPlayingFamilyView(context: context)
        } else {
            LiveActivityNowPlayingView(context: context)
        }
    }
}


extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Gym"))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa", thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 39,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: false
        )
    }

    fileprivate static var testing2: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa",  thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 50,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: false
        )
    }

    fileprivate static var theater: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(
            playableContent: .init(title: "Dance the Night (From The Barbie Album)", subtitle: "Dua Lipa",  thumbnail: nil, artwork: nil, content: .init(service: .apple, id: "123", type: .track, location: nil)), isPlaying: true,
            volume: 50,
            isMuted: false,
            name: "Kitchen + 1",
            TVMode: true,
            TVSettings: .init(nightMode: false, dialogLevel: true, audioInputFormat: .dolbyAtmosDDPlus)
        )
    }
}

#Preview("Lock Screen", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
    ClicNowPlayingWidgetAttributes.ContentState.theater
}

#Preview("Lock Screen 2", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing2
}

#Preview("Lock Screen Compact", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing2
}
#endif
