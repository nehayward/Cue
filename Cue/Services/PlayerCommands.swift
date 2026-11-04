import SonosKit
import SwiftUI

/// The player's transport, as every surface gives it: the mini player, the
/// Mac window's bar, its Controls menu and Dock menu, and Cue Mini. Read
/// through `PlaybackRoute.presented`, so this device and a Sonos group are
/// one. A book's Previous and Next go back 15 and forward 30 s; a speaker's
/// group is read again after a skip, as nothing on screen may be listening
/// for its new song. One place, so a rule changed here reaches them all.
@MainActor
enum PlayerCommands {
    private static var route: PlaybackRoute { .shared }
    private static var books: AudiobookPlayer { .shared }

    /// A book is on show: not while a hand-off holds the player on its
    /// source, whose skips would race the hand-off.
    static var isBook: Bool {
        books.isPlayingBook(on: route.presented) && !route.isHolding
    }

    /// Whether Previous has something to do: a book always does.
    static var canGoPrevious: Bool {
        let controller = route.presented
        return isBook || (controller.showsPrevious && controller.canGoBack)
    }

    static var canGoNext: Bool {
        let controller = route.presented
        return isBook || (controller.showsNext && controller.hasNext)
    }

    static var previousTitle: String {
        isBook ? "Back \(Int(AudiobookPlayer.skipBackInterval)) Seconds" : "Previous"
    }

    static var nextTitle: String {
        isBook ? "Forward \(Int(AudiobookPlayer.skipForwardInterval)) Seconds" : "Next"
    }

    static var previousSymbol: String {
        isBook ? "gobackward.\(Int(AudiobookPlayer.skipBackInterval))" : "backward.fill"
    }

    static var nextSymbol: String {
        isBook ? "goforward.\(Int(AudiobookPlayer.skipForwardInterval))" : "forward.fill"
    }

    static func togglePlayback() async {
        await route.presented.togglePlayback()
    }

    static func next() async {
        if isBook {
            await books.skip(by: AudiobookPlayer.skipForwardInterval)
            return
        }
        let controller = route.presented
        await controller.next()
        await readAgain(controller.group)
    }

    static func previous() async {
        if isBook {
            await books.skip(by: -AudiobookPlayer.skipBackInterval)
            return
        }
        let controller = route.presented
        await controller.previous()
        await readAgain(controller.group)
    }

    static func toggleShuffle() async {
        let controller = route.presented
        await controller.setShuffle(!controller.isShuffled)
    }

    static func cycleRepeat() async {
        let controller = route.presented
        await controller.setRepeatMode(controller.repeatMode.next)
    }

    /// The volume of the group being heard, by `step`; up unmutes it first,
    /// as the player's + does. Nothing on this device, whose volume is the
    /// system's.
    static func nudgeSpeakerVolume(by step: Int) async {
        guard let group = route.audibleGroup, !group.coordinatorRoom.isOutputFixed else { return }
        if step > 0, group.isMuted {
            await setMuted(false, group)
        }
        group.isEditingVolume = true
        group.groupVolume = max(0, min(100, group.groupVolume + Double(step)))
        await SonosService.shared.setRelativeGroupVolume(ip: group.ip, volume: step)
        try? await Task.sleep(for: .milliseconds(400))
        group.isEditingVolume = false
    }

    /// Sonos's group mute, every room in it at once. Shown at once on the
    /// rooms too, as Play On's All Speakers does; the poll confirms it.
    static func setMuted(_ mute: Bool, _ group: GroupRoom) async {
        group.holdMute(mute)
        for room in group.rooms where room.isMuted != mute {
            room.holdMute(mute)
        }
        await SonosService.shared.setGroupMute(group: group, mute: mute)
    }

    private static func readAgain(_ group: GroupRoom?) async {
        guard let group else { return }
        try? await SonosService.shared.updateGroups(from: [group])
    }
}
