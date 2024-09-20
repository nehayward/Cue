#if canImport(ActivityKit)
import AppIntents
import WidgetKit
import SonosKit
import SwiftUI
import VibesDS

@available(iOS 18.0, *)
struct LiveActivityNowPlayingFamilyView: View {
    @Environment(\.activityFamily) var activityFamily
    var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    
    @AppStorage("isCompact", store: UserDefaults(suiteName: "group.com.clic")) private var isCompact: Bool = false
    
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
                    }
                    Spacer()
                    Button(intent: TogglePlaybackIntent(room: context.attributes.room)) {
                        Image(systemName: "playpause.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    Button(intent: NextIntent(room: context.attributes.room)) {
                        Image(systemName: "forward.fill")
                            .frame(width: 24, height: 24)
                    }
                    .buttonBorderShape(.circle)
                    .tint(.primary)
                    
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
