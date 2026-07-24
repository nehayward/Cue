#if os(iOS) && !targetEnvironment(macCatalyst)
import Defaults
import SonosKit
import SwiftUI

/// Decides which group the system Now Playing card mirrors, and when the silent
/// session is worth holding at all.
///
/// Target group: the one the user has selected, falling back to whichever group
/// is playing. Selecting a speaker in the app therefore re-points the Lock
/// Screen, and with nothing selected the card follows the music.
///
/// The session is dropped as soon as the target has nothing loaded. Holding
/// `.playback` is not free — it interrupts other audio on the phone — so an idle
/// system gets the audio session back rather than a card showing an empty
/// speaker.
private struct NowPlayingSessionModifier: ViewModifier {
    // The shared instances rather than `@Environment`: this modifier is applied
    // at the root, outside where `ClicApp` injects them. Both are `@Observable`,
    // so reading them from `sessionKey` still registers observation.
    private var sonosService: SonosService { SonosService.shared }
    private var router: Router { Router.main }
    @AppStorage(AppStorageKeys.lockScreenNowPlaying) private var enabled: Bool = false

    private var targetGroup: GroupRoom? {
        let selected = router.selectedID.flatMap { id in
            sonosService.groups.first(where: { $0.coordinatorID == id })
        }
        // The selection sticks around after the user leaves a player, so an
        // idle selected speaker hands the card to whatever is actually playing.
        if let selected, isMirrorable(selected) { return selected }
        return sonosService.groups.first { $0.coordinatorRoom.isPlaying && isMirrorable($0) }
    }

    /// TV mode has no transport to mirror, and an empty track means the speaker
    /// is idle — neither is worth an audio session.
    private func isMirrorable(_ group: GroupRoom) -> Bool {
        guard !group.TVMode else { return false }
        return !group.coordinatorRoom.track.isEmpty || group.coordinatorRoom.radioStation != nil
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: sessionKey, initial: true) {
                guard enabled, let group = targetGroup else {
                    NowPlayingSessionService.shared.stop()
                    return
                }
                NowPlayingSessionService.shared.start(group: group, sonosService: sonosService)
            }
            // Safety net for state that didn't come off the socket — the
            // foreground poll, or an in-app transport tap on a group whose
            // socket dropped. `refresh()` is a no-op when the card already
            // matches, so this costs a string compare.
            .onChange(of: mirrorKey) {
                NowPlayingSessionService.shared.refresh()
            }
    }

    /// Only identity-level changes belong here — track and transport updates
    /// reach the card over the socket, without restarting anything.
    private var sessionKey: String {
        guard enabled else { return "off" }
        return targetGroup?.coordinatorID ?? "none"
    }

    private var mirrorKey: String {
        guard enabled, let room = targetGroup?.coordinatorRoom else { return "" }
        return "\(room.track.unique)|\(room.isPlaying)|\(room.radioStation ?? "")"
    }
}

extension View {
    func nowPlayingSession() -> some View {
        modifier(NowPlayingSessionModifier())
    }
}
#else
import SwiftUI

extension View {
    func nowPlayingSession() -> some View { self }
}
#endif
