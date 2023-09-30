import AppIntents
import WidgetKit
import SonosKit
import SwiftUI

struct LiveActivityNowPlayingView: View {
    @State var context: ActivityViewContext<ClicNowPlayingWidgetAttributes>
    var body: some View {

//                Image(uiImage: UIImage(data: context.state.imageData)!)
//                    .resizable()
//                    .frame(width: 80, height: 80)
//                    .clipShape(RoundedRectangle(cornerRadius: 12))
//                    .padding(4)


                VStack(alignment: .center) {
                    Label(context.attributes.room.name, systemImage: "hifispeaker.fill")
                        .blendMode(.hardLight)
                    HStack {
                        Button(intent: PlayPauseIntent(room: context.attributes.room)) {
                            Image(systemName: "playpause.fill")
                                .padding(2)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.secondary)

                        Button(intent: NextIntent(room: context.attributes.room)) {
                            Image(systemName: "forward.fill")
                                .padding(2)
                        }
                        .buttonStyle(.borderedProminent)
                        .buttonBorderShape(.circle)
                        .tint(.secondary)

                        HStack(spacing: 32) {
                            Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: -3)) {
                                Image(systemName: "minus")
                            }
                            .buttonStyle(.borderless)
                            .buttonBorderShape(.circle)
                            .tint(.white)
                            Button(intent: SetRelativeGroupVolumeIntent(room: context.attributes.room, volume: 3)) {
                                Image(systemName: "plus")
                            }
                            .buttonStyle(.borderless)
                            .buttonBorderShape(.circle)
                            .tint(.white)
                        }
                        .padding(8)
                        .background(.secondary, in: Capsule())
                    }

//                    Text(context.state.trackName)
//                        .blendMode(.hardLight)
//                        .bold()
//                        .lineLimit(2)
//                    Text(context.state.trackName)
//                        .blendMode(.hardLight)
//                        .lineLimit(1)

                    HStack {
                        Image(systemName: "speaker.wave.3.fill", variableValue: context.state.volume/100)
                            .foregroundStyle(.thickMaterial)
                            .contentTransition(.symbolEffect(.automatic))
                            .font(.caption)
                        ProgressView(value: Double(context.state.volume), total: 100)
                            .tint(.accentColor)
                        Text("\(context.state.volume, specifier: "%0.f")")
                            .foregroundStyle(.thickMaterial)
                            .font(.caption)
                            .contentTransition(.numericText())
                    }
//                    .padding([.leading,.trailing])
            }
            .padding()
            .fontDesign(.rounded)
//            .background {
//                Image(uiImage: UIImage(data: context.state.imageData)!)
//                            .resizable()
//                            .blur(radius: 20)
//                            .ignoresSafeArea()
//                            .frame(maxWidth: .infinity, maxHeight: .infinity)
//                            .overlay {
//                                Rectangle()
//                                    .ignoresSafeArea()
//                                    .foregroundStyle(.ultraThinMaterial)
//                            }
//            }
//            .overlay(alignment: .bottomTrailing) {
//                VStack(alignment: .center) {
//                    Button(intent: PlayPauseIntent(room: context.attributes.room)) {
//                        Image(systemName: "playpause.fill")
//                            .padding(2)
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .buttonBorderShape(.circle)
//                    .tint(.secondary)
//
//                    Button(intent: NextIntent(room: context.attributes.room)) {
//                        Image(systemName: "forward.fill")
//                            .padding(2)
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .buttonBorderShape(.circle)
//                    .tint(.secondary)
//                }
//            }

    }
}

extension ClicNowPlayingWidgetAttributes {
    fileprivate static var preview: ClicNowPlayingWidgetAttributes {
        ClicNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: "", name: "Kitchen", ip: "1298212", volume: 10))
    }
}

extension ClicNowPlayingWidgetAttributes.ContentState {
    fileprivate static var testing: ClicNowPlayingWidgetAttributes.ContentState {
        ClicNowPlayingWidgetAttributes.ContentState(date: .now, isPlaying: false, trackName: "Dance the Night (From The Barbie Album)", imageData: UIImage(named: "barbie")!.jpegData(compressionQuality: 0.8)!, volume: 39)
     }
}

#Preview("Content View", as: .content, using: ClicNowPlayingWidgetAttributes.preview) {
    LiveActivityNowPlayingWidget()
} contentStates: {
    ClicNowPlayingWidgetAttributes.ContentState.testing
}
