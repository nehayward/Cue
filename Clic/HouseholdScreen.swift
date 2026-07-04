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
                    Task { await scanForNew() }
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
            refreshHouseholds()
        }
    }

    private var householdList: some View {
        List {
            Section {
                ForEach(households) { household in
                    householdRow(for: household)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                sonosService.removeHousehold(id: household.id)
                                refreshHouseholds()
                                alertService.showAlert(with: "Household removed")
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            Button {
                                renameText = household.name
                                editingHousehold = household
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
            } footer: {
                Text("Tap to switch Sonos systems. Swipe left to rename or remove. Tap \(Image(systemName: "arrow.clockwise")) to scan for new systems on this network.")
            }
        }
        .contentMargins(.top, EdgeInsets(), for: .scrollContent)
    }

    private func householdRow(for household: SonosHousehold) -> some View {
        let isActive = household.id == sonosService.activeHousehold?.id

        return Button {
            guard !isActive else { return }
            sonosService.switchHousehold(to: household.id)
            refreshHouseholds()
            alertService.showAlert(with: "Switched to \(household.name)")
        } label: {
            HStack(spacing: 14) {
                ZStack {
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
                .frame(width: 32, height: 32)
                .shadow(color: .black.opacity(0.15), radius: 2, x: 0, y: 1)

                VStack(alignment: .leading, spacing: 2) {
                    Text(household.name)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("Last connected \(household.lastConnected, style: .relative) ago")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                Task { await scanForNew() }
            } label: {
                Text("Scan for Sonos")
            }
            .buttonStyle(.bordered)
            .tint(.accentColor)
        }
    }

    @MainActor
    private func refreshHouseholds() {
        households = sonosService.knownHouseholds
            .sorted { $0.lastConnected > $1.lastConnected }
    }

    @MainActor
    private func scanForNew() async {
        isScanning = true
        defer { isScanning = false }
        _ = try? await sonosService.getGroups(useCache: false)
        refreshHouseholds()
        if households.isEmpty {
            alertService.showAlert(with: "No Sonos systems found")
        } else {
            alertService.showAlert(with: "Scan complete")
        }
    }
}

#Preview {
    NavigationStack {
        HouseholdScreen()
            .withEnvironments()
    }
}
