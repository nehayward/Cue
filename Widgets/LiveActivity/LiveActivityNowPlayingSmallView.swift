#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

@available(iOS 18.0, *)
struct LiveActivityNowPlayingFamilyView: View {
    @Environment(\.activityFamily) var activityFamily
    let context: ActivityViewContext<CueNowPlayingWidgetAttributes>

    var body: some View {
        switch activityFamily {
        case .medium:
            if #available(iOS 26.2, *) {
                LiveActivityNowPlayingViewPre27(context: context)
            } else if #available(iOS 26, *) {
                LiveActivityNowPlayingView26(context: context)
            } else {
                LiveActivityNowPlayingView(context: context)
            }
        case .small:
            LiveActivityNowPlayingSmallView(context: context)
        @unknown default:
            fatalError("Implement this \(activityFamily)")
        }
    }
}

struct LiveActivityNowPlayingSmallView: View {
    @State var context: ActivityViewContext<CueNowPlayingWidgetAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.name)
                .font(.caption)
                .fontDesign(.rounded)
                .frame(maxWidth: .infinity, alignment: .center)
            if context.state.TVSettings == nil {
                HStack {
                    VStack {
                        if let image = ArtworkManager.shared.getImage(name: context.state.name) {
                            Image(uiImage: image)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                                .frame(width: 48, height: 48)
                                .overlay(alignment: .bottomTrailing) {
                                    context.state.playableContent.content.service.icon
                                        .frame(width: 8, height: 8, alignment: .bottomLeading)
                                        .padding([.bottom, .trailing], 4)
                                }
                                .animation(.spring, value: context.state)
                        } else {
                            RoundedRectangle(cornerRadius: 4)
                                .frame(width: 48, height: 48)
                        }
                    }.overlay {
                        if context.state.isMuted {
                            RoundedRectangle(cornerRadius: 4)
                                .foregroundStyle(.ultraThinMaterial)
                                .overlay {
                                    Image(systemName: "speaker.slash.fill")
                                }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: 0) {
                        Button(intent: PlaybackIntent(room: context.attributes.room)) {
                            Image(systemName: "playpause.fill")
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 24, height: 24)
                        }
                        .tint(.primary)
                        .buttonStyle(.liveActivity)
                        
                        Button(intent: NextIntent(room: context.attributes.room)) {
                            Image(systemName: "forward.fill")
                                .frame(width: 24, height: 24)
                        }
                        .tint(.primary)
                        .buttonStyle(.liveActivity)
                    }
                }
            }
            if let settings = context.state.TVSettings {
                Text(settings.audioInputFormat.description)
            }
        }
        .font(dynamicTypeSize < .medium ? .caption : .body)
        .padding()
        .frame(maxWidth: .infinity)
    }
}
#endif
