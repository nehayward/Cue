import AppIntents
import CloudStorage
import SonosKit
import SwiftUI
import UIKit

struct ControlLiveActivityIntent: AppIntent & LiveActivityIntent {
    static var title: LocalizedStringResource = "Control Live Activity"
    static var description = IntentDescription(
        "Control a Live Activity, start or stop a live activity for a group.",
        categoryName: "Live Activity"
    )
    static var authenticationPolicy: IntentAuthenticationPolicy = .alwaysAllowed
    static private var liveActivityManager = LiveActivityManagerFactory.shared

    @Parameter(title: "Sonos Speaker") var room: SonosDeviceEntity?
    @Parameter(title: "Control Live Activity", default: .toggle) var control: ControlOption

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$control) Live Activity for \(\.$room)")
    }

    init(room: SonosDeviceEntity) {
        self.room = room
    }

    init() {}

    func perform() async throws -> some IntentResult & ShowsSnippetView {
        guard CloudStorageSync.shared.bool(for: "com.clic.subscriptions") ?? false else {
            return .result(
                view: Link(
                    "Subscribe to Clic Super to Unlock Tap Here",
                    destination: URL(string: "clic://subscribe")!
                ).font(.title).multilineTextAlignment(.center).tint(.accentColor))
        }

        guard let room, let coordinatorRoom = await SonosService.shared.getGroupCoordinatorWithRoom(roomID: room.id) else {
            throw IntentError.message("Failed to lookup Room")
        }

        switch control {
        case .start:
            await Self.liveActivityManager.createActivity(
                id: coordinatorRoom.coordinatorID)
            await Self.liveActivityManager.refresh()
        case .stop:
            await Self.liveActivityManager.stop(
                id: coordinatorRoom.coordinatorID)
        case .toggle:
            await Self.liveActivityManager.toggle(
                id: coordinatorRoom.coordinatorID)
            await Self.liveActivityManager.refresh()
        }

        return .result()
    }
}

#if !os(visionOS)
    @available(iOS 18.0, *)
    extension ControlLiveActivityIntent: ControlConfigurationIntent {}
#endif
