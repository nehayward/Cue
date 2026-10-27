import MusicSearchKit
import SonosKit
import SwiftUI

/// Onboarding's third page — shows the music services Cue supports, with a
/// checkmark for those the user has authorized in Sonos and a dashed circle
/// for the rest. If nothing matches, surfaces an "Open Sonos App" CTA so the
/// user can add a service without leaving the flow.
struct ServicesStep: View {
    let installed: Set<SonosServiceType>
    var isActive: Bool = true
    var advance: () -> Void

    @State private var rowsIn = false

    /// Pairs the Sonos-side service type with the Cue-side `MediaSearchService`
    /// it maps to, derived from the shared `sonosServiceType` mapping
    /// (MediaSearchService+Sonos.swift) — a new music backend added there
    /// shows up here automatically. Library is skipped: it has no Sonos
    /// counterpart to detect.
    private let mapping: [(SonosServiceType, MediaSearchService)] = MediaSearchService.supported.compactMap { service in
        service.sonosServiceType.map { ($0, service) }
    }

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

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Your Music Services")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text(hasAnySupported
                     ? "Services with a checkmark are ready in Cue."
                     : "Add a music service in the Sonos app to play in Cue.")
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
}
