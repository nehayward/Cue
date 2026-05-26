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
    /// `swGen` per household IP — 2 for Sonos S2 systems, 1 for S1. Populated
    /// alongside `roomsForIP` in `loadHouseholds`. Nil if the device info
    /// fetch fails (legacy speaker, network blip).
    @State private var swGenForIP: [String: Int] = [:]
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
                householdList
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
            Label("No Sonos Systems Found", systemImage: "house.slash")
        } description: {
            Text("Make sure your Sonos speakers are powered on and on the same Wi-Fi.")
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

    private var householdList: some View {
        List {
            Section {
                ForEach(Array(sortedHouseholdIPs.enumerated()), id: \.element) { index, ip in
                    householdRow(for: ip, index: index + 1)
                }
            } footer: {
                Text("Tap to switch Sonos systems. The selected one drives playback and discovery.")
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
    }

    /// Single household row — house glyph + "Household N" + "N speakers"
    /// subtitle, matching the layout used by `SpeakerSettingsListView`.
    /// A green checkmark marks the currently-selected household.
    private func householdRow(for ip: String, index: Int) -> some View {
        let rooms = roomsForIP[ip] ?? []
        let isCurrent = sonosService.preferredHouseHold != nil && selectedIP == ip

        return Button {
            guard !isCurrent else { return }
            Task {
                selectedIP = ip
                sonosService.preferredHouseHold = await sonosService.getHouseID(for: ip)
                alertService.showAlert(with: "Switched Sonos system")
                try? await sonosService.load(useCache: false)
            }
        } label: {
            HStack(spacing: 14) {
                // Tile shows the S1/S2 label once we know it; falls back to
                // the gradient home icon while the deviceInfo fetch is in
                // flight. Black-on-white treatment for the version label
                // reads cleaner than the blue gradient.
                ZStack {
                    if let badge = systemBadge(for: ip) {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black)
                        Text(badge)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.white)
                    } else {
                        RoundedRectangle(cornerRadius: 8)
                            .fill(LinearGradient(
                                colors: [Color(red: 0.4, green: 0.6, blue: 0.95),
                                         Color(red: 0.25, green: 0.45, blue: 0.85)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            ))
                        Image("home.fill")
                            .resizable()
                            .scaledToFit()
                            .foregroundStyle(.white)
                            .padding(7)
                    }
                }
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                // Speaker names ARE the household identifier — Sonos doesn't
                // expose a user-set household name, so listing the rooms is
                // the most recognizable thing we can show. The subtitle
                // doubles as a tap-affordance hint ("Switch system" /
                // "Current system") so the row's action is obvious.
                VStack(alignment: .leading, spacing: 2) {
                    Text(speakerNamesSummary(for: rooms))
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text(isCurrent ? "Current system" : "Switch system")
                        .font(.caption)
                        .foregroundStyle(isCurrent ? .secondary : Color.accentColor)
                }

                Spacer()

                if isCurrent {
                    Image(systemName: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Returns "S2" or "S1" for the given household, based on the swGen
    /// reported by the household's first reachable speaker. Returns nil while
    /// the deviceInfo lookup is still pending or if it failed.
    private func systemBadge(for ip: String) -> String? {
        guard let gen = swGenForIP[ip] else { return nil }
        return gen >= 2 ? "S2" : "S1"
    }

    /// Comma-joined speaker names for the household. Caps at 4 names + a
    /// "+N more" suffix so the subtitle stays readable on small screens
    /// when a single household has many speakers.
    private func speakerNamesSummary(for rooms: [Room]) -> String {
        guard !rooms.isEmpty else { return "No speakers" }
        let names = rooms.map(\.name).sorted()
        let displayLimit = 4
        if names.count <= displayLimit {
            return names.formatted(.list(type: .and))
        }
        let visible = names.prefix(displayLimit).joined(separator: ", ")
        let remaining = names.count - displayLimit
        return "\(visible) +\(remaining) more"
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

            // One deviceInfo fetch per household to pick up `swGen` (S1 vs S2).
            // Runs in parallel with whatever else loadHouseholds is doing in
            // the next iteration, so it doesn't block the list from rendering.
            Task { @MainActor in
                if let info = await SonosService.shared.deviceInfo(for: ip) {
                    swGenForIP[ip] = info.swGen
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        HouseholdScreen()
            .withEnvironments()
    }
}
