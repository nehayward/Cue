import Defaults
import MusicSearchKit
import SonosKit
import SubscriptionKit
import SwiftUI

/// Root onboarding sheet. Owns the per-step navigation (forward, and back
/// with the button top left), the services chosen, and the completion
/// bookkeeping (`hasOnboarded`, `monitor()` and Apple Music's alert let go on
/// dismiss). Each step page lives in its own file:
///
///  - `WelcomeStep.swift` — splash + Get Started
///  - `ServicesStep.swift` — where the music is: the services to use, which
///    is where Apple Music's alert comes up, if Apple Music is chosen
///  - `PlexStep.swift` — Plex sign-in + default library pick (only when Plex
///    is chosen and not set up)
///  - `SubsonicSetupStep.swift`, `AudiobookshelfSetupStep.swift`,
///    `FilesSetupStep.swift` — the same for each of those chosen and not set
///    up, on `SetupPage`, each with Set Up Later
///  - `SonosQuestionStep.swift` — do you have Sonos? Sets the Sonos preference
///  - `DiscoveryStep.swift` — Local Network permission, searching, found/denied/notFound
///  - `ReadyStep.swift` — what's set up, and Start Listening
///  - `PaywallStep.swift` — CuePaywall wrapper (held back for now)
///  - `EmailStep.swift` — optional newsletter capture (held back for now)
///
/// The player comes first (CLAUDE.md, Product Priorities), so the services
/// are asked before the speakers, and saying no to Sonos still ends set up.
///
/// Supporting visual atoms (`MeshBackground`, `ShockwaveLogo`, `FloatingAppIcon`,
/// `SearchPulse`, `StateGlyph`, `DiscoveredSpeakerList`, `PrimaryPillButton`,
/// `glassPill`, and the shared `ServiceChoiceRow`) also each have their own
/// file. Debug launch-arg helpers are in `OnboardingDebug.swift`.
struct WelcomeScreen: View {
    enum Step: Int, CaseIterable {
        case welcome, services, plex, subsonic, audiobookshelf, files, sonos, discovery, ready, paywall, email
    }

    /// A change of page, set a pass ahead of `step`: the page leaving takes
    /// its transition from the last pass it was drawn in, so the direction
    /// has to be on it before it goes.
    private struct Move: Equatable {
        let step: Step
        let isBack: Bool
    }

    @Environment(SonosService.self) private var sonosService
    @Environment(SubscriptionService.self) private var subscriptionService
    @Environment(CoreFeatures.self) private var coreFeatures
    @Environment(MusicSearchService.self) private var musicSearchService
    @Environment(\.dismiss) private var dismiss
    @AppStorage(GroupStorageKeys.hasOnboarded, store: GroupStorageKeys.storage) private var hasOnboarded: Bool = false

    @State private var step: Step = .welcome
    @State private var move: Move?
    /// The pages come to, for Back.
    @State private var history: [Step] = []
    /// What the services page chose, kept for coming back to it.
    @State private var chosenServices: Set<MediaSearchService>?
    /// The set-up pages the services chosen need, in order, settled as the
    /// services page is left.
    @State private var setupSteps: [Step] = []

    var body: some View {
        ZStack {
            MeshBackground()
                .ignoresSafeArea()

            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // A layer of its own over the pages, so Back and Close stay put
            // while a page slides: as overlays on the pages they went with
            // each one.
            VStack {
                HStack {
                    if showsBack {
                        OnboardingCircleButton(systemName: "chevron.backward", label: "Back") {
                            HapticManager.shared.fireHaptic(.selection)
                            goBack()
                        }
                        .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    }
                    Spacer()
                    if ![.ready, .paywall].contains(step) {
                        // Closing early still marks onboarding complete —
                        // users found the repeat re-presentation annoying
                        // and can restart setup from Preferences if they
                        // need to.
                        OnboardingCircleButton(systemName: "xmark", label: "Close") {
                            HapticManager.shared.fireHaptic(.selection)
                            dismiss()
                        }
                        .transition(.opacity)
                    }
                }
                .padding(.top, 8)
                .padding(.horizontal, 16)
                Spacer()
            }
            .animation(.easeInOut(duration: 0.25), value: showsBack)
            .animation(.easeInOut(duration: 0.25), value: step)
        }
        .fontDesign(.rounded)
        // Force users to use the X button — no swipe-down dismiss, so they
        // can't accidentally bail mid-onboarding.
        .interactiveDismissDisabled()
        .onChange(of: move) { _, move in
            guard let move else { return }
            withAnimation(stepAnimation) { step = move.step }
        }
        .onDisappear {
            // However it ends, Apple Music may ask from here on: a screen
            // that read nothing while it was held reads again.
            AppleMusicPermission.isHeld = false
            guard !OnboardingDebug.forceShow else { return }
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
            // will start finding speakers if they granted it later. It does
            // nothing when the user said they have no Sonos.
            sonosService.monitor()
        }
    }

    private var stepAnimation: Animation {
        .spring(response: 0.6, dampingFraction: 0.85)
    }

    private var showsBack: Bool {
        !history.isEmpty && ![.welcome, .ready, .paywall].contains(step)
    }

    /// One step view at a time. Each case is given its own `.id()` so SwiftUI
    /// treats it as a fresh view identity on `step` change.
    @ViewBuilder
    private var stepContent: some View {
        switch step {
        case .welcome:
            WelcomeStep(advance: { goTo(.services) })
                .id(Step.welcome)
                .transition(slideTransition)
        case .services:
            ServicesStep(initial: chosenServices, advance: finishServices)
                .id(Step.services)
                .transition(slideTransition)
        case .plex:
            PlexStep(advance: { finishSetup(.plex) })
                .id(Step.plex)
                .transition(slideTransition)
        case .subsonic:
            SubsonicSetupStep(advance: { finishSetup(.subsonic) })
                .id(Step.subsonic)
                .transition(slideTransition)
        case .audiobookshelf:
            AudiobookshelfSetupStep(advance: { finishSetup(.audiobookshelf) })
                .id(Step.audiobookshelf)
                .transition(slideTransition)
        case .files:
            FilesSetupStep(advance: { finishSetup(.files) })
                .id(Step.files)
                .transition(slideTransition)
        case .sonos:
            SonosQuestionStep(answer: answerSonosQuestion)
                .id(Step.sonos)
                .transition(slideTransition)
        case .discovery:
            DiscoveryStep(advance: { goTo(.ready) }, skip: { goTo(.ready) })
                .id(Step.discovery)
                .transition(slideTransition)
        case .ready:
            let chosen = MediaSearchService.supported.filter { chosenServices?.contains($0) == true }
            ReadyStep(
                services: chosen,
                // Chosen, but passed by with Set Up Later.
                pending: chosen.filter { !$0.isAuthorized(on: []) },
                finish: { dismiss() }
            )
            .id(Step.ready)
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

    /// Forward slides in from the trailing edge, Back from the leading one.
    private var slideTransition: AnyTransition {
        let isBack = move?.isBack == true
        return .asymmetric(
            insertion: .move(edge: isBack ? .leading : .trailing),
            removal: .move(edge: isBack ? .trailing : .leading)
        )
    }

    /// What's chosen is what Search, Browse and the tabs offer. Nothing
    /// chosen leaves everything as it was, so a skip doesn't switch it all
    /// off. Each service chosen that isn't set up gets its page next.
    private func finishServices(_ chosen: Set<MediaSearchService>) {
        chosenServices = chosen
        if !chosen.isEmpty {
            coreFeatures.enableOnly(chosen)
            SearchSelectionStore.shared.selection = SelectedSearchServices([CoreFeatures.preferredDefaultService(from: chosen)])
        }
        setupSteps = [.plex, .subsonic, .audiobookshelf, .files].filter { needsSetup($0, chosen: chosen) }
        goTo(setupSteps.first ?? .sonos)
    }

    /// Whether `step` sets up a service chosen that isn't set up yet.
    private func needsSetup(_ step: Step, chosen: Set<MediaSearchService>) -> Bool {
        switch step {
        case .plex:
            let plexReady = PlexAuthenticator.shared.authToken != nil && musicSearchService.plexServerID != nil
            return chosen.contains(.plex) && (!plexReady || OnboardingDebug.showsPlexStep)
        case .subsonic:
            return chosen.contains(.subsonic) && !SubsonicAPI.shared.isConfigured
        case .audiobookshelf:
            return chosen.contains(.audiobookshelf) && !AudiobookshelfAPI.shared.isConfigured
        case .files:
            return chosen.contains(.files) && !FilesLibraryService.shared.isConfigured
        default:
            return false
        }
    }

    /// A set-up page done or passed by: the next one, then the speakers.
    private func finishSetup(_ step: Step) {
        guard let index = setupSteps.firstIndex(of: step), index + 1 < setupSteps.count else {
            goTo(.sonos)
            return
        }
        goTo(setupSteps[index + 1])
    }

    /// The answer is the Sonos preference. Yes turns it on without starting
    /// the search: the discovery page explains the Local Network prompt
    /// before it appears. No leaves it off, so nothing touches the network,
    /// and skips the speaker pages.
    private func answerSonosQuestion(_ hasSonos: Bool) {
        sonosService.setEnabled(hasSonos, startMonitoring: false)
        goTo(hasSonos ? .discovery : .ready)
    }

    private func goTo(_ next: Step) {
        history.append(step)
        move = Move(step: next, isBack: false)
    }

    private func goBack() {
        guard let previous = history.popLast() else { return }
        move = Move(step: previous, isBack: true)
    }
}

/// The round glass buttons in onboarding's top corners: Back and Close.
struct OnboardingCircleButton: View {
    let systemName: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.callout.weight(.semibold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
                .overlay {
                    Circle().strokeBorder(.white.opacity(0.2), lineWidth: 1)
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

#Preview("Welcome — full") {
    WelcomeScreen()
        .withEnvironments()
}
