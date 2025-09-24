import SwiftUI
import Kingfisher

struct MediaIndicatorView: View {
    let speakerName: String
    let action: MediaAction
    
    enum MediaAction {
        case volumeUp(volume: Double)
        case volumeDown(volume: Double)
        case mute(volume: Double)
        case nextTrack(trackName: String?, imageURL: URL?)
        case previousTrack(trackName: String?, imageURL: URL?)
        
        var icon: String {
            switch self {
            case .volumeUp: return "speaker.wave.3"
            case .volumeDown: return "speaker.wave.1"
            case .mute: return "speaker.slash"
            case .nextTrack: return "forward.fill"
            case .previousTrack: return "backward.fill"
            }
        }
        
        var title: String {
            switch self {
            case .volumeUp, .volumeDown, .mute: return "Volume"
            case .nextTrack: return "Next Track"
            case .previousTrack: return "Previous Track"
            }
        }
        
        var hasVolumeInfo: Bool {
            switch self {
            case .volumeUp, .volumeDown, .mute: return true
            case .nextTrack, .previousTrack: return false
            }
        }
        
        var volume: Double? {
            switch self {
            case .volumeUp(let vol), .volumeDown(let vol), .mute(let vol): return vol
            case .nextTrack, .previousTrack: return nil
            }
        }
        
//        var trackName: String? {
//            switch self {
//            case .nextTrack(let name), .previousTrack(let name): return name
//            case .volumeUp, .volumeDown, .mute: return nil
//            }
//        }
    }
    
    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Text(speakerName)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }
            
            
            VStack(spacing: 4) {
                if action.hasVolumeInfo, let volume = action.volume {
                    HStack {
                        Text(action.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(Int(volume))")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                            .foregroundStyle(.primary)
                    }
                    VibeMiniSlider(value: .constant(volume), baseHeight: 12)
                        .frame(height: 12)
//                    ProgressView(value: volume, total: 100)
//                        .tint(.accentColor)
//                        .transaction { transaction in
//                            transaction.animation = nil
//                        }
                } else {
                    switch action {
                    case .nextTrack(let trackName, let imageURL):
                        HStack {
                            KFImage.url(imageURL)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.thinMaterial)
                                }
                                .loadDiskFileSynchronously()
                                .diskCacheExpiration(.days(1))
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(trackName ?? "")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    case .previousTrack(let trackName, let imageURL):
                        HStack {
                            KFImage.url(imageURL)
                                .placeholder {
                                    RoundedRectangle(cornerRadius: 4)
                                        .foregroundStyle(.thinMaterial)
                                }
                                .loadDiskFileSynchronously()
                                .diskCacheExpiration(.days(1))
                                .fade(duration: 0.2)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .frame(width: 48, height: 48)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                            Text(trackName ?? "")
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    default:
                        EmptyView()
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    MediaIndicatorView(speakerName: "Spa", action: .volumeUp(volume: 2.0))
    MediaIndicatorView(speakerName: "Spa", action: .volumeDown(volume: 2.0))
    MediaIndicatorView(speakerName: "Spa", action: .nextTrack(trackName: "Taylor", imageURL: URL(string: "https://upload.wikimedia.org/wikipedia/en/c/c7/Dua_Lipa_-_Dance_the_Night.png")))
    MediaIndicatorView(speakerName: "Spa", action: .previousTrack(trackName: "", imageURL: nil))
}
