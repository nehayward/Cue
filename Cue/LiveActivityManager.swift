#if canImport(ActivityKit) && !targetEnvironment(macCatalyst)
import ActivityKit
import Defaults
import Foundation
import SonosKit
import MusicSearchKit
import SwiftUI

@Observable
final class LiveActivityManager: LiveActivityManageable {
    private let sonosService: SonosService
    private let artworkManager: ArtworkManager = .shared
    private let disabledActivitiesKey = "disabledLiveActivities"
    
    private var createTask: Task<Void,Error>? = nil
    /// Ends anything already on screen the moment the switch goes off. Lives
    /// here rather than at whatever flipped it, so nothing that turns Live
    /// Activities off has to remember to clean up after itself.
    private var enabledObserver: Task<Void, Never>? = nil

    /// The global switch. Nothing here knows *why* it moved — Preferences and
    /// Lock Screen Controls both just write the preference. Shared suite, so the
    /// widget intents that start activities from another process see it too.
    private var isEnabled: Bool { GroupStorageKeys.defaults.liveActivitiesEnabled }

    private var disabledActivities: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(disabledActivities), forKey: disabledActivitiesKey)
        }
    }

    init(sonosService: SonosService = .shared) {
        self.disabledActivities = Set(UserDefaults.standard.stringArray(forKey: disabledActivitiesKey) ?? [])
        self.sonosService = sonosService

        enabledObserver = Task { [weak self] in
            // Both locals live inside the task body: a `var` captured by a
            // `@Sendable` closure can't be mutated from it.
            let store = GroupStorageKeys.defaults
            // `didChangeNotification` fires for every write to the suite, so act
            // only on an actual transition of this one flag.
            var lastKnown = store.liveActivitiesEnabled
            for await _ in NotificationCenter.default.notifications(
                named: UserDefaults.didChangeNotification,
                object: store
            ) {
                let enabled = store.liveActivitiesEnabled
                guard enabled != lastKnown else { continue }
                lastKnown = enabled
                guard !enabled else { continue }
                await self?.endAll()
            }
        }
    }

    deinit {
        enabledObserver?.cancel()
    }

    func refresh() async {
        let activities = Activity<CueNowPlayingWidgetAttributes>.activities
        guard !activities.isEmpty else { return }

        // Tapping a control in the Live Activity (a volume number, say) runs its
        // intent in the app's process — and when the app isn't already running,
        // iOS launches it fresh in the background just for that intent. In that
        // process `groups` is still empty because nothing has loaded the
        // topology yet, so load it before judging any activity. Without this an
        // empty topology reads as "these rooms are gone" and dismisses the very
        // activity the user just tapped.
        if sonosService.groups.isEmpty {
            try? await sonosService.load(useCache: true)
        }

        // Still empty: the system is unreachable (off Wi-Fi, speakers asleep,
        // load failed). That's indistinguishable from "the room went away", so
        // leave every activity alone rather than tearing them all down.
        guard !sonosService.groups.isEmpty else { return }

        for activity in activities {
            guard !isActivityDisabled(id: activity.attributes.room.id) || activity.attributes.requiresManualDismissal else {
                await activity.end(activity.content, dismissalPolicy: .immediate)
                continue
            }

            guard let group = sonosService.groups.first(where: { $0.coordinatorRoom.id == activity.attributes.room.id}) else {
                // Only this activity's room is missing from a topology we did
                // load — end this one. Ending the whole set here took unrelated
                // rooms' activities down with it.
                await activity.end(activity.content, dismissalPolicy: .immediate)
                continue
            }

            let trackReadAt = Date.now
            async let track = sonosService.getTrack(ip: group.coordinatorRoom.ip)
            async let playbackInfo = sonosService.getPlaybackInfo(ip: group.coordinatorRoom.ip)
            async let groupVolume = sonosService.getGroupVolume(ip: group.coordinatorRoom.ip)
            async let isMuted = sonosService.isMuted(for: group)

            // One unreachable speaker shouldn't stop the remaining activities
            // from refreshing.
            guard let info = try? await (track, playbackInfo, groupVolume, isMuted) else { continue }
            // Mid-skip the model already shows where the presses are headed;
            // this read may still be of the song being left.
            if let track = info.0, await !sonosService.skipHoldsTrack(on: group, read: track, at: trackReadAt) {
                // A skip preview carries the real song's id but none of its
                // metadata, so it's replaced rather than kept.
                let isShownTrack = group.coordinatorRoom.track.trackID == track.trackID
                    && !group.coordinatorRoom.track.isSkipPreview
                if isShownTrack, !group.isEditingPlayback {
                    group.coordinatorRoom.updatePlaybackPosition(track.playbackPosition)
                } else if !isShownTrack {
                    group.coordinatorRoom.track = track
                    group.coordinatorRoom.updatePlaybackPosition(track.playbackPosition)
                }
            }
            // A failed read says nothing about whether it's playing.
            if info.1 != .unknown {
                group.coordinatorRoom.setPlaying(info.1 == .playing, source: .poll)
            }
            group.groupVolume = info.2
            group.isMuted = info.3 ?? false
            
            if group.coordinatorRoom.track == .empty {
                artworkManager.removeArtwork(coordinatorRoom: group.nameWithCount)
            } else {
                await artworkManager.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL, trackID: group.coordinatorRoom.track.trackID)
            }

            if group.TVMode {
                group.tvSettings = try? await sonosService.getTVSettings(group: group)
            }
            
            let contentState = group.toContentState
            let activityContent = ActivityContent(state: contentState, staleDate: .now.addingTimeInterval(1))
            await activity.update(activityContent)
            
//            if !group.coordinatorRoom.isPlaying && !group.TVMode {
//                await activity.end(activity.content, dismissalPolicy: .after(.now.addingTimeInterval(60)))
//            }
        }
    }

    func createActivity(shouldLoad: Bool = true ) {
        createTask?.cancel()
        createTask = Task {
            if Task.isCancelled { return }
            guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
            let activities = Activity<CueNowPlayingWidgetAttributes>.activities
            if shouldLoad {
                try? await sonosService.load(useCache: true)
            }

            for group in sonosService.groups.filter({ $0.coordinatorRoom.isPlaying || $0.TVMode }) {
                guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
                    continue
                }
                guard !isActivityDisabled(id: group.coordinatorRoom.id) else {
                    continue
                }

                await ArtworkManager.shared.downScale(coordinatorRoom: group.nameWithCount, url: group.coordinatorRoom.track.artworkURL, trackID: group.coordinatorRoom.track.trackID)

                let sonosAttribute = CueNowPlayingWidgetAttributes(room: SonosDeviceEntity(id: group.coordinatorRoom.id,
                                                                                            ip: group.coordinatorRoom.ip,
                                                                                            name: group.nameWithCount))
                if group.TVMode {
                    group.tvSettings = try? await sonosService.getTVSettings(group: group)
                }

                let contentState = group.toContentState
                let activityContent = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(60), relevanceScore: Double(activities.count))

                do {
                    if Task.isCancelled { return }
                    let activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
                    print("Created Live Activity for \(activity.content) \(activity.attributes)")
                } catch (let error) {
                    print("Error requesting Live Activity \(error.localizedDescription).")
                }
            }
        }
    }

    func createActivity(id: String) async {
        guard isEnabled, ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        
        let activities = Activity<CueNowPlayingWidgetAttributes>.activities
        try? await sonosService.load(useCache: true)

        guard let group = await sonosService.getGroupCoordinatorWithRoom(roomID: id) else {
            return
        }

        let sonosAttribute = CueNowPlayingWidgetAttributes(
            room: SonosDeviceEntity(
                id: group.coordinatorRoom.id,
                ip: group.coordinatorRoom.ip,
                name: group.nameWithCount
            ),
            requiresManualDismissal: true
        )

        if group.TVMode {
            group.tvSettings = try? await sonosService.getTVSettings(group: group)
        }

        let contentState = group.toContentState
        
        let activityContent = ActivityContent(state: contentState, staleDate: Date.now.addingTimeInterval(60), relevanceScore: activities.isEmpty ? 0 : 1)
        guard !activities.contains(where: { $0.attributes.room.id == group.coordinatorRoom.id }) else {
            print("Failed")
            return
        }

        do {
            let activity = try Activity.request(attributes: sonosAttribute, content: activityContent)
            print("Created Live Activity from ID: \(activity.content) \(activity.attributes)")
        } catch (let error) {
            print("Error requesting Live Activity \(error.localizedDescription).")
        }
    }

    func reset() async {
        for activity in Activity<CueNowPlayingWidgetAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }
    
    func stop(id: String) async {
        for activity in Activity<CueNowPlayingWidgetAttributes>.activities {
            if id == activity.attributes.room.id {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
    }
    
    func endAll() async {
        for activity in Activity<CueNowPlayingWidgetAttributes>.activities {
            await activity.end(activity.content, dismissalPolicy: .immediate)
        }
    }
    
    func toggle(id: String) async {
        let activities = Activity<CueNowPlayingWidgetAttributes>.activities
        let matchingActivities = activities.filter { $0.attributes.room.id == id }
        
        if matchingActivities.isEmpty {
            await createActivity(id: id)
        } else {
            for activity in matchingActivities {
                await activity.end(activity.content, dismissalPolicy: .immediate)
            }
        }
    }

    func isActivityDisabled(id: String) -> Bool {
        return  disabledActivities.contains(id)
    }
    
    func disableActivity(id: String) {
        var current = disabledActivities
        current.insert(id)
        disabledActivities = current
        Task {
            await stop(id: id)
        }
    }
    
    func enableActivity(id: String) {
        var current = disabledActivities
        current.remove(id)
        disabledActivities = current
    }
    
    func toggleActivityEnabled(id: String) {
        if isActivityDisabled(id: id) {
            enableActivity(id: id)
        } else {
            disableActivity(id: id)
        }
    }
}

#endif
