import SwiftUI

/// Why the paywall came up: the gate that was hit, for the card at its top
/// and the comparison row it lights, and what happened, when there's more
/// to say than the gate's name (part of an album downloading, say).
struct PaywallReason: Equatable {
    let feature: GatedFeature
    var detail: String?
}

/// The paywall's opening card when a gate brought it up: what was held
/// back and why, and for downloads the free meter as it stands, so "50 of
/// 50" is the first thing read rather than a sales pitch.
struct PaywallReasonCard: View {
    let reason: PaywallReason

    private var manager: DownloadManager { .shared }

    private var isDownloads: Bool {
        reason.feature == .unlimitedDownloads || reason.feature == .downloads
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } icon: {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
            }
            if isDownloads {
                let limit = DownloadManager.freeSongLimit
                ProgressView(value: Double(min(manager.heldAgainstLimit, limit)), total: Double(limit))
                    .progressViewStyle(.linear)
                    .tint(Color.accentColor)
                let onWatch = WatchSyncService.shared.heldOnWatch
                if onWatch > 0 {
                    Text("\(onWatch) of them on your Apple Watch")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                        .monospacedDigit()
                }
            }
            if let message {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.65))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(0.5), lineWidth: 1)
        )
    }

    private var title: String {
        switch reason.feature {
        case .unlimitedDownloads, .downloads:
            let limit = DownloadManager.freeSongLimit
            let held = manager.heldAgainstLimit
            return held >= limit ? "All \(limit) free downloads used" : "\(held) of \(limit) free downloads used"
        case .bookDownloads:
            return "Books download with Cue Super"
        case .allRooms:
            return "Every room with Cue Super"
        default:
            return "\(reason.feature.title) is part of Cue Super"
        }
    }

    private var message: String? {
        if let detail = reason.detail { return detail }
        switch reason.feature {
        case .unlimitedDownloads, .downloads:
            return "Cue Super keeps every song you download, on this iPhone and your Apple Watch, with no limit."
        case .bookDownloads:
            return "Keep Plex and Audiobookshelf books on this iPhone and your Apple Watch, to listen with no connection."
        case .allRooms:
            return "Without Super, Cue plays on one Sonos group: the one with your first room."
        default:
            return nil
        }
    }

    private var symbol: String {
        switch reason.feature {
        case .unlimitedDownloads, .downloads: "arrow.down.circle.fill"
        case .bookDownloads: "books.vertical.fill"
        case .allRooms: "hifispeaker.2.fill"
        case .scenes: "sparkles"
        default: "lock.fill"
        }
    }
}
