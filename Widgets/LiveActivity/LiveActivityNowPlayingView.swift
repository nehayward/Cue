import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var updateTransition: AnyTransition {
        switch context.state.update {
        case .next:
            return .push(from: .trailing)
        case .previous:
            return .push(from: .leading)
        case .refresh:
            return .opacity
        }
    }

    var body: some View {
        VStack {
            HStack {
                Label(context.state.name, systemImage: "hifispeaker.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Link(destination: URL(string: "clic://search?id=\(context.attributes.room.id)")!) {
                    Image(systemName: "magnifyingglass.circle.fill")
                        .imageScale(.large)
                        .bold()
                }
                Button(intent: RefreshIntent()) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill")
                        .imageScale(.large)
                        .bold()
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .tint(.primary)
            }
            .padding(.bottom, 8)
            Text(context.state.trackName)
                .lineLimit(0)
                .bold()
                .invalidatableContent()
                .id(context.state.trackName)
                .transition(updateTransition)
            Text(context.state.artist)
                .foregroundStyle(.secondary)
                .lineLimit(0)
                .invalidatableContent()
                .id(context.state.artist)
                .transition(updateTransition)
            HStack {
                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                    Image(systemName: "minus")
                        .bold()
                }
                .buttonStyle(.plain)
                .buttonBorderShape(.circle)
                .tint(.primary)

                ProgressView(value: Double(context.state.volume), total: 100)
                    .tint(.accentColor)
                    .invalidatableContent()
                Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                    Image(systemName: "plus")
                        .bold()
                }
                .buttonStyle(.plain)
                .tint(.primary)
                .buttonBorderShape(.circle)
            }
            .padding([.bottom], 4)
            HStack(spacing: 24) {
                Button(intent: PreviousIntent(room: context.attributes.room)) {
                    Image(systemName: "backward.end.fill")
                }
                Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                    Image(systemName: "playpause.fill")
                        .imageScale(.large)
                }
                Button(intent: NextIntent(room: context.attributes.room)) {
                    Image(systemName: "forward.end.fill")
                }
            }
            .tint(.primary)
            .buttonStyle(.borderless)
        }
        .font(dynamicTypeSize < .medium ? .caption : .body)
        .padding()
        .activityBackgroundTint(.clear)
        .background(.background.opacity(0.4))
        .widgetURL(URL(string: "clic://device?id=\(context.attributes.room.id)"))
    }
}

extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", ip: "1298212", name: "Kitchen", volume: 10))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(trackName: "Dance the Night (From The Barbie Album)",
                                                    artist: "Dua Lipa",
                                                    volume: 39,
                                                    name: "Kitchen + 1")
    }
}

#Preview("Lock Screen", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
