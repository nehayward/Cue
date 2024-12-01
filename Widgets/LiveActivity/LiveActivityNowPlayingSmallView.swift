#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

@available(iOS 18.0, *)
struct LiveActivityNowPlayingFamilyView: View {
    @Environment(\.activityFamily) var activityFamily
    let context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false

    var body: some View {
        switch activityFamily {
        case .medium:
            LiveActivityNowPlayingView(context: context)
        case .small:
            LiveActivityNowPlayingSmallView(context: context)
        @unknown default:
            fatalError("Implement this \(activityFamily)")
        }
    }
}

struct LiveActivityNowPlayingSmallView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(context.state.name)
                .font(.caption)
                .fontDesign(.rounded)
            if context.state.TVSettings == nil {
                HStack {
                    Group {
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
                    Spacer()
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
        .background(.background.opacity(0.4))
    }
}
#endif
