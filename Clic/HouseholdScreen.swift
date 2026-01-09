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
    @State private var selectedIP: String?

    private var sortedHouseholdIPs: [String] {
        Array(houseHoldsIPs).sorted()
    }

    var body: some View {
        Group {
            if !isLoaded {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if houseHoldsIPs.isEmpty {
                emptyStateView
            } else {
                householdListView
            }
        }
        .task {
            await loadHouseholds()
        }
        .navigationTitle("Households")
        .navigationBarTitleDisplayMode(.inline)
        .fontDesign(.rounded)
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Households Found", systemImage: "house.slash")
        } description: {
            Text("Make sure your Sonos speakers are powered on and connected to the same network.")
        } actions: {
            Button {
                Task { await loadHouseholds() }
            } label: {
                Text("Try Again")
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }

    private var householdListView: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(Array(sortedHouseholdIPs.enumerated()), id: \.element) { index, ip in
                    householdCard(for: ip, index: index + 1)
                }
            }
            .padding()
        }
    }

    private func householdCard(for ip: String, index: Int) -> some View {
        let rooms = roomsForIP[ip] ?? []
        let isCurrentHousehold = sonosService.preferredHouseHold != nil && selectedIP == ip

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "house.fill")
                    .font(.title3)
                    .foregroundStyle(.accent)
                Text("Household \(index)")
                    .font(.headline)
                Spacer()
                if isCurrentHousehold {
                    Text("Current")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(.accent, in: Capsule())
                }
            }
            .padding()
            .background(Color(.systemGray6).opacity(0.5))

            Divider()

            VStack(spacing: 0) {
                ForEach(rooms) { room in
                    HStack(spacing: 12) {
                        Image(systemName: "hifispeaker.fill")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .frame(width: 32)

                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name)
                                .font(.body)
                                .fontWeight(.medium)
                            Text(room.ip)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 12)

                    if room.id != rooms.last?.id {
                        Divider()
                            .padding(.leading, 56)
                    }
                }
            }

            Divider()

            Button {
                Task {
                    selectedIP = ip
                    sonosService.preferredHouseHold = await sonosService.getHouseID(for: ip)
                    alertService.showAlert(with: "Switched to Household \(index)")
                    try? await sonosService.load(useCache: false)
                }
            } label: {
                HStack {
                    Image(systemName: isCurrentHousehold ? "checkmark.circle.fill" : "arrow.right.circle.fill")
                    Text(isCurrentHousehold ? "Currently Selected" : "Select This Household")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
            }
            .disabled(isCurrentHousehold)
            .foregroundStyle(isCurrentHousehold ? Color.secondary : Color.accent)
            .background(Color(.systemGray6).opacity(0.3))
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isCurrentHousehold ? Color.accentColor.opacity(0.5) : Color.clear, lineWidth: 2)
        )
    }

    private func loadHouseholds() async {
        isLoaded = false
        defer { isLoaded = true }

        self.houseHoldsIPs = await SonosService.shared.getAllHouseholdsIPs()

        for ip in houseHoldsIPs {
            guard let groups = try? await SonosService.shared.getGroups(with: ip) else {
                continue
            }
            roomsForIP[ip] = groups.flatMap(\.rooms)
        }
    }
}

#Preview {
    NavigationStack {
        HouseholdScreen()
            .withEnvironments()
    }
}
