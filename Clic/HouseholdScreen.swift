import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS

struct HouseholdScreen: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService

    @State private var isLoaded: Bool = false
    @State private var houseHoldsIPs: Set<String> = []
    @State private var roomsForIP: [String: String] = [:]

    var body: some View {
        List {
            ForEach(Array(houseHoldsIPs), id: \.self) { ip in
                Button {
                    Task {
                        sonosService.preferredHouseHold = await sonosService.getHouseID(for: ip)
                        alertService.showAlert(with: "Set Preferred Household")
                        try? await sonosService.load(useCache: false)
                    }
                } label: {
                    Text("\(roomsForIP[ip] ?? "")")
                }
            }
        }
        .task {
            isLoaded = false
            defer { isLoaded = true }
            self.houseHoldsIPs = await SonosService.shared.getAllHouseholdsIPs()

            for ip in houseHoldsIPs {
                guard let group = try? await SonosService.shared.getGroups(with: ip) else {
                    print("Failed")
                    return
                }
                roomsForIP[ip] = group.flatMap(\.rooms).map(\.name).joined(separator: ", ")
            }
        }
        .navigationTitle("Households")
        .overlay {
            if !isLoaded {
                ProgressView()
            }
        }
    }
}

#Preview {
    HouseholdScreen()
        .environment(SonosService.shared)
}
