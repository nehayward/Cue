import SwiftUI
import SonosKit

struct TVModeView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var group: GroupRoom

    var body: some View {

        VStack(alignment: .leading) {
            HStack {
                Image(systemName: group.rooms.count > 1 ? "hifispeaker.2.fill" : "hifispeaker.fill")
                Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
            }
            HStack {
                Button {

                } label: {
                    Image(systemName: "moon.zzz")
                        .symbolVariant(.fill)
                }
                .buttonBorderShape(.circle)
                .buttonStyle(.bordered)
                Button {

                } label: {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                }
                .buttonBorderShape(.circle)
                .buttonStyle(.bordered)
            }
        }
        .padding()
        .onAppear {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                sonosService.monitor()
            }
        }
        .tag(group.coordinatorID)
    }
}

#Preview {
    List {
        TVModeView(group: .constant(.garage))
            .environment(SonosService())
    }
    .listStyle(.carousel)
}

