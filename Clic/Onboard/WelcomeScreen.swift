import Analytics
import Defaults
import MusicSearchKit
import SonosKit
import SubscriptionKit
import SwiftUI

/// Root onboarding sheet. Owns the per-step navigation, the discovered-services
/// state, and the bail-out / completion bookkeeping (`hasOnboarded`,
/// `didBailOut`, `monitor()` on dismiss). Each step page lives in its own file:
///
///  - `WelcomeStep.swift` — splash + Get Started
///  - `DiscoveryStep.swift` — Local Network permission, searching, found/denied/notFound
///  - `ServicesStep.swift` — list of music services with checkmarks
///  - `PaywallStep.swift` — ClicPaywall wrapper (skipped when already subscribed)
///  - `EmailStep.swift` — optional newsletter capture (final step)
///
/// Supporting visual atoms (`MeshBackground`, `ShockwaveLogo`, `FloatingAppIcon`,
/// `SearchPulse`, `StateGlyph`, `DiscoveredSpeakerList`, `ServiceRow`,
/// `PrimaryPillButton`, `glassPill`) also each have their own file. Debug
/// launch-arg helpers are in `OnboardingDebug.swift`.
struct WelcomeScreen: View {
    enum Step: Int, CaseIterable {
        case welcome, discovery, services, paywall, email
    }

    @Environment(SonosService.self) private var sonosService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false
    @AppStorage(AppStorageKeys.mediaService) private var musicSearchSelection: MediaSearchService = .apple

    @State private var step: Step = .welcome
    @State private var installedServices: Set<SonosServiceType> = []
    /// Set when the user closes onboarding before reaching Services. Used
    /// only to distinguish the analytics event (bailed vs completed) —
    /// `hasOnboarded` is written either way so the sheet doesn't
    /// re-present on next launch. Users can re-run setup from Preferences.
    @State private var didBailOut = false

    var body: some View {
        ZStack {
            MeshBackground()
                .ignoresSafeArea()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .topTrailing) {
                    if step != .paywall {
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            // Closing before Services is recorded as a
                            // "bailed" analytics event but still marks
                            // onboarding complete — users found the repeat
                            // re-presentation annoying and can restart
                            // setup from Preferences if they need to.
                            if step == .welcome || step == .discovery {
                                didBailOut = true
                            }
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(.white.opacity(0.85))
                                .frame(width: 34, height: 34)
                                .background(.ultraThinMaterial, in: Circle())
                                .overlay {
                                    Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Close")
                        .padding(.top, 8)
                        .padding(.trailing, 16)
                    }
                }
        }
        .fontDesign(.rounded)
        // Force users to use the X button — no swipe-down dismiss, so they
        // can't accidentally bail mid-onboarding.
        .interactiveDismissDisabled()
        .task {
            // Funnel entry point — fires once when the sheet first appears.
            Analytics.shared.track(OnboardingEvent.started)
        }
        .onDisappear {
            guard !OnboardingDebug.forceShow else { return }
            Analytics.shared.track(didBailOut ? OnboardingEvent.bailed : OnboardingEvent.completed)
            // Mark onboarding done regardless of bail vs complete — the
            // sheet shouldn't keep re-presenting on every launch. Direct
            // write + synchronize on the app-group store because
            // @AppStorage's setter alone races view teardown on
            // fullScreenCover dismiss.
            GroupStorageKeys.storage?.set(true, forKey: GroupStorageKeys.hasOnboarded)
            GroupStorageKeys.storage?.synchronize()
            hasOnboarded = true
            // Kick discovery off — even if the user bailed before granting
            // Local Network, monitor() is harmless without permission and
            // will start finding speakers if they granted it later.
            sonosService.monitor()
        }
    }

    private var stepAnimation: Animation {
        .spring(response: 0.6, dampingFraction: 0.85)
    }

    /// One step view at a time. Each case is given its own `.id()` so SwiftUI
    /// treats it as a fresh view identity on `step` change.
    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep(advance: { goTo(.discovery) })
                .id(Step.welcome)
                .transition(slideTransition)
        case .discovery:
            DiscoveryStep(advance: advanceFromDiscovery)
                .id(Step.discovery)
                .transition(slideTransition)
        case .services:
            ServicesStep(installed: installedServices, advance: advanceFromServices)
                .id(Step.services)
                .transition(slideTransition)
        case .paywall:
            PaywallStep()
                .id(Step.paywall)
                .transition(slideTransition)
        case .email:
            EmailStep(advance: { dismiss() }, source: "ios-onboarding")
                .id(Step.email)
                .transition(slideTransition)
        }
    }

    private var slideTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: .trailing),
            removal: .move(edge: .leading)
        )
    }

    private func advanceFromDiscovery() {
        Task {
            let installed: [SonosServiceType]
            if OnboardingDebug.mockNoServices {
                installed = []
            } else {
                installed = await fetchInstalledServices()
            }
            await MainActor.run {
                let installedSet = Set(installed)
                installedServices = installedSet
                // Sync per-service enabled flags so search/browse only surface
                // services the user has actually authorized in Sonos. Apple
                // Music and Library stay on regardless (they don't need a
                // Sonos service).
                coreFeatures.syncEnabledServices(from: installedSet)
                // Default the active search service to Spotify if available,
                // then Apple Music — matches what most users want without
                // forcing them into Preferences.
                musicSearchSelection = CoreFeatures.preferredDefaultService(from: installedSet)
                goTo(.services)
            }
        }
    }

    /// Fetches the user's authorized Sonos music services with retries.
    ///
    /// `SonosService.services()` reads from the keychain, which gets
    /// populated asynchronously: `onServerListening()` starts a media-server
    /// listener, subscribes to Sonos's ZoneGroupTopology, decrypts the
    /// pushed payload, then writes the MediaServer list to keychain. On a
    /// cold launch or if the decrypter / parser hiccups, the first call
    /// returns empty. Try a few times with growing delays before settling.
    private func fetchInstalledServices() async -> [SonosServiceType] {
        // Total worst case ~4.5s (0 + 1.5 + 3.0). Most users get data on
        // the first or second attempt; the third covers slow Wi-Fi or a
        // first-launch keychain write race.
        let delays: [UInt64] = [0, 1_500, 3_000]
        for delay in delays {
            if delay > 0 {
                try? await Task.sleep(for: .milliseconds(Int(delay)))
            }
            let services = await sonosService.services()
            if !services.isEmpty {
                logServices(services)
                return services.map(\.type)
            }
        }
        // Truly empty (no services authorized) — surface the empty-state UI.
        #if DEBUG
        print("[Sonos Service] No media servers found after 3 attempts — keychain empty.")
        #endif
        return []
    }

    private func logServices(_ services: [MediaServer]) {
        #if DEBUG
        for service in services {
            print("""
            [Sonos Service]
              name: \(service.name)
              type: \(service.type)
              serviceId: \(service.serviceId)
              udn (id): \(service.id)
            """)
        }
        #endif
    }

    /// Services → next. Subscribed users skip the paywall entirely and land
    /// straight on the newsletter step; everyone else gets the paywall first.
    private func advanceFromServices() {
        if subscriptionService.subscription.isActive {
            goTo(.email)
        } else {
            goTo(.paywall)
        }
    }

    private func goTo(_ next: Step) {
        // Track "viewed" events at the moment a step is entered. Discovery
        // entry isn't tracked here — `DiscoveryStep` fires more granular
        // started/succeeded/notFound/denied events itself.
        switch next {
        case .services: Analytics.shared.track(OnboardingEvent.viewedServices)
        // Reuse the existing top-level `viewedPaywall` event (which fires
        // for paywall views anywhere in the app) instead of creating an
        // onboarding-specific duplicate.
        case .paywall:  Analytics.shared.track(AnalyticEvents.viewedPaywall)
        default: break
        }
        withAnimation(stepAnimation) { step = next }
    }
}

#Preview("Welcome — full") {
    WelcomeScreen()
        .withEnvironments()
}
