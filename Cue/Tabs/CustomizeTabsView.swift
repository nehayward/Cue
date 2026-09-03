import MusicSearchKit
import SwiftUI

/// Which providers have a tab of their own, and in what order. A provider
/// added here gets a tab in the tab bar and, on iPad and Mac, a sidebar
/// section with its collections as tabs. Reached from the sidebar's bottom
/// bar and from the Browse tab's provider menu.
struct CustomizeTabsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoreFeatures.self) private var coreFeatures

    @State private var store = TabProviderStore.shared

    private var availableProviders: [MediaSearchService] {
        store.availableProviders(enabledIn: coreFeatures)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.providers.isEmpty {
                        Text("No providers in the tab view yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.providers, id: \.self) { service in
                        HStack(spacing: 12) {
                            providerLabel(
                                for: service,
                                subtitle: coreFeatures.isEnabled(service)
                                    ? service.tabCollectionsDescription
                                    : "Turned off in Services"
                            )
                            Spacer(minLength: 0)
                            // A button rather than swipe-to-delete alone:
                            // there is no swipe on Mac.
                            Button {
                                withAnimation(.spring(response: 0.3)) {
                                    store.remove(service)
                                }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Remove \(service.title)")
                        }
                        .opacity(coreFeatures.isEnabled(service) ? 1 : 0.5)
                    }
                    .onDelete { offsets in
                        store.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        store.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("In Tabs")
                } footer: {
                    Text("Each provider gets a tab of its own. On iPad and Mac it is a section in the sidebar, with its collections as tabs. Drag to reorder.")
                }

                Section {
                    if availableProviders.isEmpty {
                        Text("Every provider that can be a tab is already one.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(availableProviders, id: \.self) { service in
                        Button {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            withAnimation(.spring(response: 0.3)) {
                                store.add(service)
                            }
                        } label: {
                            HStack(spacing: 12) {
                                providerLabel(for: service, subtitle: service.tabCollectionsDescription)
                                Spacer(minLength: 0)
                                Image(systemName: "plus.circle.fill")
                                    .foregroundStyle(.accent)
                            }
                        }
                        .tint(.primary)
                    }
                } header: {
                    Text("Available")
                } footer: {
                    Text("Providers switched on in Settings › Services whose library browses by collection. This arrangement applies only on this device.")
                }
            }
            .navigationTitle("Customize Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Done", systemImage: "checkmark")
                            .labelStyle(.iconOnly)
                            .fontWeight(.semibold)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func providerLabel(for service: MediaSearchService, subtitle: String) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 2) {
                Text(service.title)
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            service.iconForMusicService
                .frame(width: 24, height: 24)
        }
    }
}

#Preview {
    CustomizeTabsView()
        .withEnvironments()
}
