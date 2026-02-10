import SwiftUI
import SonosKitMini

struct HouseholdScreen: View {
    @Environment(SonosMiniService.self) var sonosService

    @State private var isLoaded: Bool = false
    @State private var houseHoldsIPs: Set<String> = []
    @State private var roomNames: [String: [String]] = [:]
    @State private var selectedIP: String?
    @State private var switchedMessage: String?

    private var sortedHouseholdIPs: [String] {
        Array(houseHoldsIPs).sorted()
    }

    var body: some View {
        List {
            if !isLoaded {
                loadingView
            } else if houseHoldsIPs.isEmpty {
                emptyStateSection
            } else {
                householdSections
            }
        }
        .task {
            await loadHouseholds()
        }
        .navigationTitle("Households")
    }

    private var loadingView: some View {
        ProgressView("Searching...")
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
    }

    private var emptyStateSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "house.slash")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No Households Found")
                    .font(.headline)
                Text("Make sure your speakers are on and connected to the same network.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical)

            Button {
                Task { await loadHouseholds() }
            } label: {
                Text("Try Again")
            }
        }
    }

    @ViewBuilder
    private var householdSections: some View {
        ForEach(Array(sortedHouseholdIPs.enumerated()), id: \.element) { index, ip in
            householdSection(for: ip, index: index + 1)
        }

        if let switchedMessage {
            Section {
                Label(switchedMessage, systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.caption2)
            }
        }
    }

    private func householdSection(for ip: String, index: Int) -> some View {
        let names = roomNames[ip] ?? []
        let isCurrentHousehold = sonosService.preferredHouseHold != nil && selectedIP == ip

        return Section {
            if !names.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "hifispeaker.fill")
                        .foregroundStyle(.secondary)
                        .font(.caption2)
                    Text(names.joined(separator: ", "))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .listRowBackground(Color.clear)
            }

            selectButton(ip: ip, index: index, isCurrentHousehold: isCurrentHousehold)
        } header: {
            Text("Household \(index) (\(names.count))")
        }
    }

    private func selectButton(ip: String, index: Int, isCurrentHousehold: Bool) -> some View {
        Button {
            Task {
                selectedIP = ip
                sonosService.preferredHouseHold = await sonosService.getHouseID(for: ip)
                switchedMessage = "Switched to Household \(index)"
                try? await sonosService.loadWatch(useCache: false)
            }
        } label: {
            if isCurrentHousehold {
                Label("Current", systemImage: "checkmark.circle.fill")
            } else {
                Label("Select", systemImage: "arrow.right.circle.fill")
            }
        }
        .disabled(isCurrentHousehold)
        .buttonStyle(.borderedProminent)
        .tint(isCurrentHousehold ? .gray : .accentColor)
        .listRowBackground(Color.clear)
    }

    private func loadHouseholds() async {
        isLoaded = false
        defer { isLoaded = true }

        self.houseHoldsIPs = await SonosMiniService.shared.getAllHouseholdsIPs()

        for ip in houseHoldsIPs {
            guard let groups = try? await SonosMiniService.shared.getGroups(with: ip) else {
                continue
            }
            roomNames[ip] = groups.flatMap(\.rooms).map(\.name)
        }
    }
}

#Preview {
    HouseholdScreen()
        .environment(SonosMiniService.shared)
}
