import SwiftUI
import SonosKit

struct TVModeView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var group: GroupRoom

    var body: some View {
        Section {
            HStack {
                Button {

                } label: {
                    Image(systemName: "moon.zzz")
//                        .symbolVariant(.fill)
                }
                .buttonStyle(.bordered)
                .buttonBorderShape(.circle)
                Button {

                } label: {
                    Image(systemName: "moon.zzz")
                        .symbolVariant(.fill)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                Button {

                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
            }

            Button {

            } label: {
                Image(systemName: "bubble.left.and.text.bubble.right")
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
        }
        .tag(group.coordinatorID)
    }
}

#Preview {
    List {
        TVModeView(group: GroupRoom(id: "", coordinatorID: "", rooms: [Room(id: "", ip: "", name: "Kitchen")]))
            .environment(SonosService())
    }
}

