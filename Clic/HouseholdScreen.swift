import SwiftUI
import SonosKit
import SubscriptionKit
import VibesDS

struct HouseholdScreen: View {
    @Environment(SonosService.self) var sonosService
    @Environment(AlertService.self) var alertService

    @State private var households: [SonosHousehold] = []
    @State private var isScanning: Bool = false
    @State private var editingHousehold: SonosHousehold? = nil
    @State private var renameText: String = ""

    /// Speaker rooms per household id, fetched lazily from each household's last
    /// known IP so the row can show which speakers it contains. Reachable homes
    /// populate; an offline home just shows its name + last-connected.
    @State private var roomsByHousehold: [String: [Room]] = [:]
    /// swGen per household id — 2 for Sonos S2, 1 for S1. Nil until the deviceInfo
    /// fetch lands (or if it fails for an offline home).
    @State private var swGenByHousehold: [String: Int] = [:]

    var body: some View {
        Group {
            if households.isEmpty && !isScanning {
                emptyStateView
            } else {
                householdList
            }
        }
        .navigationTitle("Households")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await scanForNew(announce: true) }
                } label: {
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .disabled(isScanning)
            }
        }
        .fontDesign(.rounded)
        .sheet(item: $editingHousehold) { household in
            renameSheet(for: household)
        }
        .onAppear {
            // Show stored homes instantly, no waiting on the network.
            refreshHouseholds()
        }
        .task {
            // Enrich stored rows with speaker names / S1-S2, then scan the network
            // for any new homes (e.g. a friend's system) and merge them in.
            await enrichHouseholds(households)
            await scanForNew()
        }
    }

    private var householdList: some View {
        List {
            Section {
                ForEach(households) { household in
                    householdRow(for: household)
                        .contextMenu {
                            Button {
                                beginRename(household)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            Button(role: .destructive) {
                                delete(household)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                delete(household)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            Button {
                                beginRename(household)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
            } footer: {
                Text("Tap to switch Sonos systems. Long-press or swipe for rename and remove. Tap \(Image(systemName: "arrow.clockwise")) to scan for new systems on this network.")
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
    }

    private func householdRow(for household: SonosHousehold) -> some View {
        let isActive = household.id == sonosService.activeHousehold?.id
        let rooms = roomsByHousehold[household.id] ?? []

        return Button {
            guard !isActive else { return }
            sonosService.switchHousehold(to: household.id)
            refreshHouseholds()
            alertService.showAlert(with: "Switched to \(household.name)")
        } label: {
            HStack(spacing: 14) {
                // S1/S2 badge tile once known; otherwise the gradient home glyph.
                ZStack {
                    if let badge = systemBadge(for: household.id) {
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

                VStack(alignment: .leading, spacing: 2) {
                    Text(household.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    // Speaker names when we have them (identifies which system this
                    // is), otherwise fall back to the last-connected timestamp.
                    Text(subtitle(for: household, rooms: rooms))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Spacer()

                if isActive {
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

    /// "S2"/"S1" for the household once its swGen is known, else nil.
    private func systemBadge(for id: String) -> String? {
        guard let gen = swGenByHousehold[id] else { return nil }
        return gen >= 2 ? "S2" : "S1"
    }

    private func subtitle(for household: SonosHousehold, rooms: [Room]) -> String {
        if !rooms.isEmpty {
            return speakerNamesSummary(for: rooms)
        }
        return "Last connected \(household.lastConnected.formatted(.relative(presentation: .named)))"
    }

    /// "(7) Living Room, Kitchen, …" — the total speaker count always leads (so it
    /// stays visible), followed by the names. The cell truncates to a single line.
    private func speakerNamesSummary(for rooms: [Room]) -> String {
        let names = rooms.map(\.name).sorted()
        guard !names.isEmpty else { return "No speakers" }
        return "(\(names.count)) \(names.joined(separator: ", "))"
    }

    @ViewBuilder
    private func renameSheet(for household: SonosHousehold) -> some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $renameText)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Rename Household")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { editingHousehold = nil }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let name = renameText.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            sonosService.renameHousehold(id: household.id, name: name)
                            refreshHouseholds()
                        }
                        editingHousehold = nil
                    }
                    .disabled(renameText.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private var emptyStateView: some View {
        ContentUnavailableView {
            Label("No Known Households", systemImage: "house.slash")
        } description: {
            Text("Tap Scan to find Sonos systems on your network.")
        } actions: {
            Button {
                Task { await scanForNew(announce: true) }
            } label: {
                Text("Scan for Sonos")
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }

    private func beginRename(_ household: SonosHousehold) {
        renameText = household.name
        editingHousehold = household
    }

    private func delete(_ household: SonosHousehold) {
        sonosService.removeHousehold(id: household.id)
        roomsByHousehold[household.id] = nil
        swGenByHousehold[household.id] = nil
        refreshHouseholds()
        alertService.showAlert(with: "Household removed")
    }

    @MainActor
    private func refreshHouseholds() {
        households = sonosService.knownHouseholds
            .sorted { $0.lastConnected > $1.lastConnected }
    }

    /// Fetches speaker names + S1/S2 for the given households from each one's last
    /// known IP, in parallel. Best-effort: offline homes simply don't populate.
    /// Scoped to a subset so the on-appear enrich (stored homes) and the post-scan
    /// enrich (only newly-found homes) don't re-fetch the same homes twice.
    @MainActor
    private func enrichHouseholds(_ toEnrich: [SonosHousehold]) async {
        await withTaskGroup(of: Void.self) { group in
            for household in toEnrich {
                let id = household.id
                let ip = household.lastKnownIP
                guard !ip.isEmpty else { continue }
                group.addTask { @MainActor in
                    if let groups = try? await SonosService.shared.getGroups(with: ip) {
                        roomsByHousehold[id] = groups.flatMap(\.rooms)
                    }
                }
                group.addTask { @MainActor in
                    if let info = await SonosService.shared.deviceInfo(for: ip) {
                        swGenByHousehold[id] = info.swGen
                    }
                }
            }
        }
    }

    /// Scans the current network for Sonos systems and merges any newly-found
    /// homes into the list. `announce` is true only for the manual refresh button
    /// so the on-appear auto-scan stays silent; the manual scan also re-adds a
    /// reachable home the user previously removed (an explicit "look again").
    @MainActor
    private func scanForNew(announce: Bool = false) async {
        guard !isScanning else { return }
        isScanning = true
        defer { isScanning = false }
        let before = Set(households.map(\.id))
        let updated = await sonosService.discoverHouseholds(includeRemoved: announce)
        households = updated.sorted { $0.lastConnected > $1.lastConnected }
        // Enrich only the newly-discovered homes; the stored ones were already
        // enriched on appear, so this avoids re-fetching (and re-stalling on
        // offline homes) every one of them.
        await enrichHouseholds(households.filter { !before.contains($0.id) })
        guard announce else { return }
        let newCount = households.filter { !before.contains($0.id) }.count
        if newCount > 0 {
            alertService.showAlert(with: newCount == 1 ? "Found a new home" : "Found \(newCount) new homes")
        } else if households.isEmpty {
            alertService.showAlert(with: "No Sonos systems found")
        } else {
            alertService.showAlert(with: "No new homes found")
        }
    }
}

#Preview {
    NavigationStack {
        HouseholdScreen()
            .withEnvironments()
    }
}
