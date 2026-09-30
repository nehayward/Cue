import Analytics
import SonosKit
import SwiftUI

/// Dedicated permission + discovery page. Owns the searching/found/denied/
/// notFound state machine, the per-group haptics, the Local Network permission
/// retry on scene-active, and the action pill that maps to each state.
struct DiscoveryStep: View {
    @Environment(SonosService.self) private var sonosService
    @Environment(\.scenePhase) private var scenePhase
    @State private var didStart = false
    /// In `mockNoGroups` mode, flips to `true` ~1.5s after the user taps
    /// Continue so the UI shows the searching state first and then transitions
    /// to "not found" — mirroring the real discovery cadence.
    @State private var mockSearchDone = false
    /// Tracks whether we've already fired the discoverySucceeded analytics
    /// event, so it doesn't re-fire on every subsequent rooms.count change.
    @State private var didTrackSuccess = false
    /// Holds the `.found` reveal until `hydrateRoomDetails()` finishes or a
    /// 200ms deadline elapses — whichever comes first. Stops the speaker rows
    /// from rendering with a placeholder model name and then text-swapping to
    /// "Sonos Move 2" mid-cascade.
    @State private var revealReady = false
    var advance: () -> Void
    /// Carries on without speakers when none were found or the network is
    /// blocked. Sonos stays on, so speakers show up once they are reachable.
    var skip: (() -> Void)? = nil

    private enum DiscoveryStatus: Hashable {
        case idle, denied, notFound, found, searching
    }

    private var discoveryStatus: DiscoveryStatus {
        if !didStart { return .idle }
        if OnboardingDebug.mockNoGroups {
            return mockSearchDone ? .notFound : .searching
        }
        if sonosService.systemState.permissionDenied { return .denied }
        if sonosService.systemState.notFound { return .notFound }
        if !sonosService.sorted.isEmpty, revealReady { return .found }
        return .searching
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header — title + subtitle both swap text based on state
            VStack(spacing: 8) {
                Text(headerTitle)
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: headerTitle)

                Text(headerSubtitle)
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.3), value: headerSubtitle)
            }
            .padding(.top, 56)
            .padding(.bottom, 28)

            // Middle stage — pulse radar / speaker list / error glyph
            ZStack {
                switch discoveryStatus {
                case .idle, .searching:
                    SearchPulse(isAnimating: discoveryStatus == .searching)
                        .transition(.opacity)
                        .id("pulse")
                case .found:
                    // Plain `.opacity` — the previous `.scale(0.96)` combined
                    // transition collided with the outgoing pulse's fade-out
                    // and made the swap feel like it stuttered.
                    DiscoveredSpeakerList(rooms: sonosService.sortedRooms)
                        .transition(.opacity)
                        .id("list")
                case .denied:
                    StateGlyph(systemName: "wifi.exclamationmark", tint: .yellow)
                        .transition(.opacity)
                        .id("denied")
                case .notFound:
                    StateGlyph(systemName: "magnifyingglass", tint: .white.opacity(0.55))
                        .transition(.opacity)
                        .id("notFound")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(.easeInOut(duration: 0.35), value: discoveryStatus)

            // Action button — per-state ZStack with cross-fades
            actionButton
                .padding(.horizontal, 28)
                .padding(.bottom, skipButtonShown ? 8 : 36)

            // A way on for someone whose speakers aren't here right now —
            // otherwise the only way out of these two states was the X.
            if skipButtonShown, let skip {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    skip()
                } label: {
                    Text("Continue Without Speakers")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.white.opacity(0.85))
                .padding(.horizontal, 28)
                .padding(.bottom, 28)
                .transition(.opacity)
            }
        }
        .onChange(of: sonosService.rooms.count) { oldCount, newCount in
            // Fire the analytics event exactly once, when the first speaker
            // arrives. Per-speaker haptics now live inside
            // `DiscoveredSpeakerList` so each tap lands in sync with the
            // row's cascade reveal.
            guard !didTrackSuccess, oldCount == 0, newCount > 0 else { return }
            didTrackSuccess = true
            Analytics.shared.track(OnboardingEvent.discoverySucceeded)

            // Kick off the media-server + Sonos event subscription as soon as
            // we have a topology. Otherwise an X-out before the user reaches
            // the end of onboarding leaves `groups` populated but no push
            // channel for transport updates — the main scene-active handler
            // only fires `onServerListening()` once `hasOnboarded` flips,
            // which a bail-out never does. Safe to call repeatedly; the
            // server short-circuits if already listening.
            sonosService.onServerListening()

            // Race hydration against a 200ms deadline before revealing the
            // list — either the model names land first (fast LAN) or we cap
            // the wait so one slow speaker can't hang the onboarding flow.
            Task {
                await withTaskGroup(of: Void.self) { group in
                    group.addTask { await sonosService.hydrateRoomDetails() }
                    group.addTask { try? await Task.sleep(for: .milliseconds(200)) }
                    _ = await group.next()
                    group.cancelAll()
                }
                revealReady = true
            }
        }
        .onChange(of: scenePhase) { _, phase in
            // If the user left for Settings to grant Local Network access and
            // came back, re-attempt discovery.
            guard phase == .active, didStart else { return }
            sonosService.monitor()
        }
        // Fire once when discovery first lands in a terminal failure state.
        // `.onChange(initial:)` with a stable guard prevents re-firing on
        // subsequent state churn.
        .onChange(of: sonosService.systemState.notFound) { _, isNotFound in
            if didStart, isNotFound {
                Analytics.shared.track(OnboardingEvent.discoveryNotFound)
            }
        }
        .onChange(of: sonosService.systemState.permissionDenied) { _, isDenied in
            if didStart, isDenied {
                Analytics.shared.track(OnboardingEvent.discoveryDenied)
            }
        }
    }

    private var skipButtonShown: Bool {
        skip != nil && [.notFound, .denied].contains(discoveryStatus)
    }

    // MARK: copy

    // The discovery page exists to answer one question: did we find your
    // speakers? Copy is framed as setup → in-progress → success or failure,
    // so each state reads as a clear outcome rather than instructional text.

    private var headerTitle: String {
        switch discoveryStatus {
        case .idle: return "Connect your Sonos"
        case .searching: return "Searching…"
        case .found:
            let n = sonosService.rooms.count
            return n == 1 ? "Connected to 1 speaker" : "Connected to \(n) speakers"
        case .denied: return "Can't reach your network"
        case .notFound: return "No Sonos found"
        }
    }

    private var headerSubtitle: String {
        switch discoveryStatus {
        case .idle: return "Tap Continue to scan your network for Sonos."
        case .searching: return "Looking for speakers on your Wi-Fi."
        case .found: return "You're all set."
        case .denied: return "Allow Local Network access in Settings to continue."
        case .notFound: return "Make sure your Sonos is powered on and on this Wi-Fi."
        }
    }

    // MARK: discovery

    private func startDiscovery() {
        if OnboardingDebug.mockNoGroups {
            mockSearchDone = false
            Task {
                try? await Task.sleep(for: .milliseconds(1500))
                mockSearchDone = true
            }
        } else {
            sonosService.monitor()
        }
    }

    @ViewBuilder
    private var actionButton: some View {
        ZStack {
            switch discoveryStatus {
            case .idle:
                PrimaryPillButton(title: "Continue") {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Analytics.shared.track(OnboardingEvent.discoveryStarted)
                    startDiscovery()
                    didStart = true
                }
                .id(DiscoveryStatus.idle)
                .transition(.opacity)
            case .denied:
                PrimaryPillButton(title: "Open Settings", action: openSettings)
                    .id(DiscoveryStatus.denied)
                    .transition(.opacity)
            case .notFound:
                PrimaryPillButton(title: "Try Again", action: startDiscovery)
                    .id(DiscoveryStatus.notFound)
                    .transition(.opacity)
            case .found:
                PrimaryPillButton(title: "Continue") {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    advance()
                }
                .id(DiscoveryStatus.found)
                .transition(.opacity)
            case .searching:
                PrimaryPillButton(title: "Searching…", isDisabled: true) { }
                    .id(DiscoveryStatus.searching)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: discoveryStatus)
    }

    private func openSettings() {
        #if canImport(UIKit)
        #if targetEnvironment(macCatalyst)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocalNetwork") {
            UIApplication.shared.open(url)
        }
        #else
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
        #endif
        #endif
    }
}
