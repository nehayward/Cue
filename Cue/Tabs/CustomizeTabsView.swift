import MusicSearchKit
import SwiftUI

/// Which providers have a tab of their own, in what order, and which of
/// their collections are tabs. A provider added here gets a tab in the tab
/// bar and, on iPad and Mac, a sidebar section with the switched-on
/// collections as tabs. Reached from the sidebar's plus button and from the
/// Browse tab's provider menu.
struct CustomizeTabsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(CoreFeatures.self) private var coreFeatures

    @State private var store = TabProviderStore.shared
    /// Providers whose collections are unfolded. Everything starts open, so
    /// the sheet shows what each section holds without a tap.
    @State private var expanded: Set<MediaSearchService> = []

    private var availableProviders: [MediaSearchService] {
        store.availableProviders(enabledIn: coreFeatures)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if store.providers.isEmpty {
                        Text("No providers in the tab view yet. Add one with the plus button.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.providers) { provider in
                        DisclosureGroup(isExpanded: expansion(of: provider.service)) {
                            ForEach(provider.service.tabCollections, id: \.self) { collection in
                                collectionRow(collection, in: provider)
                            }
                        } label: {
                            providerLabel(for: provider)
                        }
                    }
                    // Swipe, or the edit mode's minus — never a button in
                    // the row, which the row's own tap would fight.
                    .onDelete { offsets in
                        store.remove(atOffsets: offsets)
                    }
                    .onMove { source, destination in
                        store.move(fromOffsets: source, toOffset: destination)
                    }
                } header: {
                    Text("In Tabs")
                } footer: {
                    Text("Each provider is a tab of its own. On iPad and Mac it is a section in the sidebar, with the checked collections as tabs; on iPhone its tab lists them. Use Edit to reorder or remove.")
                }

                if !availableProviders.isEmpty {
                    Section {
                        ForEach(availableProviders, id: \.self) { service in
                            Button {
                                add(service)
                            } label: {
                                HStack(spacing: 12) {
                                    serviceLabel(service, subtitle: "\(service.tabCollections.count) collections")
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
                        Text("Providers switched on in Settings › Services. This arrangement applies only on this device.")
                    }
                }
            }
            .navigationTitle("Customize Tabs")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    EditButton()
                }
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(availableProviders, id: \.self) { service in
                            Button {
                                add(service)
                            } label: {
                                HStack {
                                    Text(service.title)
                                    service.image
                                }
                            }
                        }
                    } label: {
                        Label("Add Provider", systemImage: "plus")
                    }
                    .disabled(availableProviders.isEmpty)
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
            .onAppear {
                expanded = Set(store.providers.map(\.service))
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private func add(_ service: MediaSearchService) {
        HapticManager.shared.fireHaptic(.buttonPress)
        withAnimation(.spring(response: 0.3)) {
            store.add(service)
            expanded.insert(service)
        }
    }

    private func expansion(of service: MediaSearchService) -> Binding<Bool> {
        Binding {
            expanded.contains(service)
        } set: { isExpanded in
            if isExpanded {
                expanded.insert(service)
            } else {
                expanded.remove(service)
            }
        }
    }

    private func collectionRow(_ collection: ProviderCollection, in provider: TabProvider) -> some View {
        let isOn = provider.isEnabled(collection)

        return Button {
            withAnimation(.spring(response: 0.3)) {
                store.toggle(collection, for: provider.service)
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                    .fontWeight(.semibold)
                    .foregroundStyle(isOn ? Color.accent : Color.secondary)
                    .contentTransition(.symbolEffect(.automatic))
                Label(collection.title, systemImage: collection.systemImage)
                    .foregroundStyle(.primary)
            }
        }
        .tint(.primary)
        .opacity(isOn ? 1 : 0.6)
    }

    private func providerLabel(for provider: TabProvider) -> some View {
        let count = provider.collections.count
        let subtitle = coreFeatures.isEnabled(provider.service)
            ? (count == 1 ? "1 collection" : "\(count) collections")
            : "Turned off in Services"

        return serviceLabel(provider.service, subtitle: subtitle)
            .opacity(coreFeatures.isEnabled(provider.service) ? 1 : 0.5)
    }

    private func serviceLabel(_ service: MediaSearchService, subtitle: String) -> some View {
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
