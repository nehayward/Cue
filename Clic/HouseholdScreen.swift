import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS

struct HouseholdScreen: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService

    @State private var isLoaded: Bool = false
    @State private var houseHoldsIPs: Set<String> = []
    @State private var roomsForIP: [String: [Room]] = [:]

    var body: some View {
        List {
            ForEach(Array(houseHoldsIPs), id: \.self) { ip in
                Section(header: Spacer(minLength: 0)) {
                    ForEach(roomsForIP[ip] ?? []) { room in
                        Label {
                            Text(room.name)
                            Text(room.ip)
                        } icon: {
                            Image(systemName: "hifispeaker.fill")
                                .foregroundStyle(.primary)
                                .tint(.primary)
                        }
                    }
                    Button {
                        Task {
                            sonosService.preferredHouseHold = await sonosService.getHouseID(for: ip)
                            alertService.showAlert(with: "Set Preferred Household")
                            try? await sonosService.load(useCache: false)
                        }
                    } label: {
                        Text("Household \(roomsForIP[ip]?.count ?? 0)")
                            .bold()
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.accentColor)
                    .listRowBackground(Color.clear)
                }
            }
        }
        .task {
            isLoaded = false
            defer { isLoaded = true }
            self.houseHoldsIPs = await SonosService.shared.getAllHouseholdsIPs()

            for ip in houseHoldsIPs {
                guard let groups = try? await SonosService.shared.getGroups(with: ip) else {
                    print("Failed")
                    return
                }
                roomsForIP[ip] = groups
                    .flatMap(\.rooms)
            }
        }
        .navigationTitle("Households")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if !isLoaded {
                ProgressView()
            }
        }
        .environment(\.defaultMinListHeaderHeight, 0)
        .fontDesign(.rounded)
    }
}

#Preview {
    NavigationStack {
        HouseholdScreen()
            .withEnvironments()
    }
}
