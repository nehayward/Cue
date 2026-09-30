import MusicKit
import MusicSearchKit
import SonosKit
import SwiftUI

/// The services page for someone without speakers (or whose speakers weren't
/// found). Unlike `ServicesStep`, nothing here comes from a Sonos system:
/// each service is ready when this device can play it. TuneIn needs nothing,
/// Apple Music needs MusicKit access (asked for here), and Plex, Subsonic and
/// Files are set up later in Settings ▸ Services.
struct DeviceServicesStep: View {
    @Environment(MusicSearchService.self) private var musicSearchService
    @State private var rowsIn = false
    /// Bumped after the Apple Music prompt, so the rows re-read
    /// `MusicAuthorization.currentStatus`, which isn't observable.
    @State private var authorizationCheck = 0
    var advance: () -> Void

    private var services: [MediaSearchService] {
        _ = authorizationCheck
        // Ready ones first, keeping the supported order within each group.
        return MediaSearchService.supported.enumerated().sorted { l, r in
            let lReady = l.element.isAuthorized(on: [])
            let rReady = r.element.isAuthorized(on: [])
            if lReady != rReady { return lReady }
            return l.offset < r.offset
        }.map(\.element)
    }

    private var needsAppleMusic: Bool {
        _ = authorizationCheck
        return MediaSearchService.supported.contains(.apple)
            && MusicAuthorization.currentStatus != .authorized
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Text("Your Music Services")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Everything with a checkmark plays on this device.")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
            .padding(.top, 36)
            .padding(.bottom, 24)

            ScrollView {
                VStack(spacing: 10) {
                    ForEach(Array(services.enumerated()), id: \.element) { index, service in
                        ServiceRow(service: service, isAvailable: service.isAuthorized(on: []))
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
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .scrollIndicators(.hidden)

            Text("Connect Plex, Subsonic or a folder of music any time in Settings ▸ Services.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 28)
                .padding(.top, 6)

            VStack(spacing: 10) {
                if needsAppleMusic {
                    PrimaryPillButton(title: "Connect Apple Music", icon: "music.note") {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        Task {
                            _ = await musicSearchService.requestMusicAuthorization()
                            withAnimation { authorizationCheck += 1 }
                        }
                    }
                    Button(action: advance) {
                        Text("Skip for Now")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .foregroundStyle(.white.opacity(0.85))
                } else {
                    PrimaryPillButton(title: "Continue", action: advance)
                }
            }
            .padding(.horizontal, 28)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .task {
            DispatchQueue.main.async { rowsIn = true }
        }
    }
}
