import MusicSearchKit
import SwiftUI

/// One row in the `ServicesStep` list. Minimal: brand icon + service name.
/// Availability is conveyed by opacity (unavailable services dim) rather than
/// by a checkmark + dashed-circle pair — the icon and name already carry
/// enough signal.
struct ServiceRow: View {
    let service: MediaSearchService
    let isAvailable: Bool

    var body: some View {
        HStack(spacing: 14) {
            service.iconForMusicService
                .frame(width: 28, height: 28)

            Text(service.title)
                .font(.headline)
                .foregroundStyle(.white)

            Spacer(minLength: 8)

            // Subtle availability marker — present (green checkmark) for ready
            // services, hidden for the rest. No dashed-circle placeholder; the
            // dimmer opacity on unavailable rows carries that signal.
            if isAvailable {
                Image(systemName: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.green)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(isAvailable ? 1 : 0.4)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(isAvailable ? 0.08 : 0.03))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(isAvailable ? 0.14 : 0.06), lineWidth: 1)
                }
        }
        // One element per row instead of icon-then-name-then-checkmark.
        // e.g. "Spotify, Ready" / "Tidal, Not set up"
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(service.title), \(isAvailable ? "Ready" : "Not set up")")
    }
}
