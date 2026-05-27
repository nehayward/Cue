import MusicSearchKit
import SonosKit
import SwiftUI

/// Onboarding's third page — shows the music services Clic supports, with a
/// checkmark for those the user has authorized in Sonos and a dashed circle
/// for the rest. If nothing matches, surfaces an "Open Sonos App" CTA so the
/// user can add a service without leaving the flow.
struct ServicesStep: View {
    let installed: Set<SonosServiceType>
    var isActive: Bool = true
    var advance: () -> Void

    @State private var rowsIn = false

    /// Pairs the Sonos-side service type with the Clic-side `MediaSearchService`
    /// it maps to. When you add a new music backend, drop a row here.
    ///
    /// TODO: When Clic adds support for more services (Sonos Radio, SiriusXM,
    /// Pandora, Amazon Music, Bandcamp, etc.), add the matching
    /// `(SonosServiceType, MediaSearchService)` pair below.
    private let mapping: [(SonosServiceType, MediaSearchService)] = [
        (.appleMusic, .apple),
        (.spotify, .spotify),
        (.tidal, .tidal),
        (.plex, .plex),
        (.tunein, .tuneIn),
        (.soundcloud, .soundcloud)
    ]

    private var hasAnySupported: Bool {
        mapping.contains { installed.contains($0.0) }
    }

    private var sortedMapping: [(SonosServiceType, MediaSearchService)] {
        // Available services first, preserving the original order within each group
        mapping.enumerated().sorted { l, r in
            let lAvail = installed.contains(l.element.0)
            let rAvail = installed.contains(r.element.0)
            if lAvail != rAvail { return lAvail }
            return l.offset < r.offset
        }.map(\.element)
    }

    /// Known `SonosServiceType` cases the user has authorized in Sonos but
    /// Clic doesn't yet support — Pandora, SiriusXM, Bandcamp, etc. We can
    /// render these with their proper names since the enum knows the label.
    private var unsupportedKnownTypes: [SonosServiceType] {
        let mapped = Set(mapping.map(\.0))
        return installed.compactMap { type -> SonosServiceType? in
            guard !mapped.contains(type) else { return nil }
            if case .unknown = type { return nil }
            return type
        }.sorted { $0.rawValue.localizedStandardCompare($1.rawValue) == .orderedAscending }
    }

    /// `.unknown(_)` services we can't render — the raw service ID isn't a
    /// useful display name (we don't get the user-set nickname through our
    /// current pipeline). Surfaced as a small footer count instead.
    private var unknownUnsupportedCount: Int {
        installed.filter { type in
            if case .unknown = type { return true }
            return false
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Your Music Services")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(hasAnySupported
                     ? "Services with a checkmark are ready in Clic."
                     : "Add a music service in the Sonos app to play in Clic.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(sortedMapping.enumerated()), id: \.element.0) { index, pair in
                        ServiceRow(
                            service: pair.1,
                            isAvailable: installed.contains(pair.0)
                        )
                        .opacity(rowsIn ? 1 : 0)
                        .offset(y: rowsIn ? 0 : 18)
                        .animation(
                            .spring(response: 0.55, dampingFraction: 0.85)
                                .delay(Double(index) * 0.06),
                            value: rowsIn
                        )
                    }

                    // Known-but-unsupported services land here — same row
                    // shell, no checkmark, dimmed so they read as informational
                    // rather than actionable.
                    ForEach(Array(unsupportedKnownTypes.enumerated()), id: \.element.rawValue) { index, type in
                        UnsupportedServiceRow(name: type.rawValue)
                            .opacity(rowsIn ? 1 : 0)
                            .offset(y: rowsIn ? 0 : 18)
                            .animation(
                                .spring(response: 0.55, dampingFraction: 0.85)
                                    .delay(Double(index + sortedMapping.count) * 0.06),
                                value: rowsIn
                            )
                    }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 4)
                // Cap rows at ~500pt on iPad / Mac fullScreenCover so the
                // service list reads as a centered column instead of
                // stretching edge-to-edge. iPhone widths are below the cap
                // so this is a no-op there.
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)
            .mask {
                VStack(spacing: 0) {
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                        .frame(height: 12)
                    Color.black
                    LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                        .frame(height: 24)
                }
            }

            // Surface the help link whenever the user has any unsupported
            // services — known (Pandora, SiriusXM, etc.) or unknown
            // (Audible, Amazon Music, etc.). The "+N unrecognized" count
            // line only appears when there are truly-unknown ones.
            if unsupportedKnownTypes.count + unknownUnsupportedCount > 0 {
                VStack(spacing: 6) {
                    if unknownUnsupportedCount > 0 {
                        Text(unknownUnsupportedCount == 1
                             ? "1 other service we don't recognize yet."
                             : "\(unknownUnsupportedCount) other services we don't recognize yet.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.55))
                            .multilineTextAlignment(.center)
                    }

                    Button(action: openHelpPage) {
                        HStack(spacing: 4) {
                            Text("Help us add support")
                                .font(.caption.weight(.semibold))
                            Image(systemName: "arrow.up.right")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundStyle(.white.opacity(0.85))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 28)
                .padding(.top, 6)
            }

            VStack(spacing: 10) {
                if !hasAnySupported {
                    PrimaryPillButton(title: "Open Sonos App", icon: "arrow.up.forward.app") {
                        openSonosApp()
                    }
                }

                if hasAnySupported {
                    PrimaryPillButton(title: "Continue", action: advance)
                } else {
                    Button(action: advance) {
                        Text("Skip for Now")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .onChange(of: isActive, initial: true) { _, active in
            if active {
                rowsIn = false
                DispatchQueue.main.async { rowsIn = true }
            }
        }
    }

    private func openSonosApp() {
        #if canImport(UIKit)
        if let url = URL(string: "sonos://"), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        } else if let store = URL(string: "https://apps.apple.com/app/sonos/id1488977981") {
            UIApplication.shared.open(store)
        }
        #endif
    }

    /// Opens the Clic help page so users can read about supported services
    /// or request new ones. Shown whenever any unsupported service (known or
    /// unknown) is detected on the user's Sonos.
    private func openHelpPage() {
        #if canImport(UIKit)
        if let url = URL(string: "https://clic.dance/help") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

/// A row for a service we recognize but don't yet support in Clic (Pandora,
/// SiriusXM, Bandcamp). Same visual chrome as `ServiceRow` but no checkmark
/// and dimmed so it reads as informational rather than actionable.
private struct UnsupportedServiceRow: View {
    let name: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "music.note")
                .font(.title2)
                .foregroundStyle(.white.opacity(0.5))
                .frame(width: 28, height: 28)

            VStack(alignment: .leading, spacing: 1) {
                Text(name)
                    .font(.headline)
                    .foregroundStyle(.white)
                Text("Not supported in Clic yet")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.55))
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .opacity(0.55)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(.white.opacity(0.04))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(.white.opacity(0.08), lineWidth: 1)
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), not supported in Clic yet")
    }
}

