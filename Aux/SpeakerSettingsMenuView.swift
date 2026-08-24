import CloudStorage
import VibesDS
import SwiftUI
import SonosKit

struct SpeakerSettingsMenuView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService
    @Environment(Router.self) var router

    var group: GroupRoom

    var body: some View {
        if group.rooms.count > 1 {
            Menu {
                ForEach(group.rooms) { room in
                    Button {
                        router.presentedSheet = .speakerSettings(room: room)
                    } label: {
                        Text("\(room.name)")
                    }
                }
            } label: {
                Label("Settings", systemImage: "gear")
            }
        } else {
            Button {
                router.presentedSheet = .speakerSettings(room: group.coordinatorRoom)
            } label: {
                Label("Settings", systemImage: "gear")
            }
        }
    }
}

