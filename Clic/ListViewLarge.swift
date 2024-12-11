import CloudStorage
import SwiftUI
import SonosKit
import SubscriptionKit
import RevenueCat
import RevenueCatUI

struct ListViewLarge: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService
    @Environment(Router.self) var router: Router
    @Binding var selected: String?

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService
        @Bindable var router = router

        // MARK: Add Back for Debugging
//        let _ = Self._printChanges()

        List ($sonosService.sorted, selection: $selected) { $group in
            Section {
                if group.coordinatorRoom.state == .active {
                    VStack(spacing: 12) {
                        if group.TVMode {
                            TVModeViewCell(group: $group)
                        } else {
                            HStack(alignment: .top) {
                                ArtworkView(group: $group)
                                    .frame(width: 72, height: 72)
                                ZoneView(group: $group)
                                Spacer()
                                MediaControlsView(group: $group)
                            }
                        }
                        VolumeControlView(group: $group, delayDrag: true)
                    }
                    .tag(group.coordinatorID)
                    .listRowBackground(group.coordinatorID == selected ? Color(uiColor: .systemFill).clipShape(RoundedRectangle(cornerRadius: 16)) : Color(UIColor.secondarySystemGroupedBackground).clipShape(RoundedRectangle(cornerRadius: 16)))
                    .foregroundStyle(.primary)
                    .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
                    .dropDestinationPlay(on: group)
                    .paywall(enabled(group: group))
                } else {
                    Text(group.coordinatorRoom.state.reason)
                        .selectionDisabled()
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color(UIColor.secondarySystemGroupedBackground).clipShape(RoundedRectangle(cornerRadius: 16)))
                        .paywall(enabled(group: group))
                }
            } header: {
                HStack {
                    Text(group.nameWithCount)
                    if let battery = group.coordinatorRoom.battery {
                        Spacer()
                        Text((battery.percentage / 100), format: .percent)
                            .foregroundStyle(.secondary)
                        if battery.chargingState == .charging {
                            Image(systemName: "battery.100percent.bolt")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                        }
                    }
                }
                .fontDesign(.rounded)
                .headerProminence(.increased)
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .environment(\.defaultMinListRowHeight, 40)
        .animation(.interactiveSpring, value: sonosService.groups)
        .onChange(of: sonosService.sorted) { 
            if selected == nil {
                sonosService.selectedGroup = sonosService.sorted.first
                selected = sonosService.sorted.first?.coordinatorID
            }
        }
        .onChange(of: selected) {
            if let id = selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == id }) {
                sonosService.selectedGroup = sonosService.sorted[index]
            }
        }
        #if targetEnvironment(macCatalyst)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentedSheet = .settings()
                } label: {
                    Image(systemName: "switch.2")
                }
            }
        }
        .overlay(alignment: .center) {
            if sonosService.sorted.isEmpty, sonosService.parserError == nil {
                ProgressView()
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                if sonosService.systemState.permissionDenied {
                    Button {
                        // MARK: Settings Action
                        #if canImport(UIKit)
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    } label: {
                        Label("Local Network Permission Needed", systemImage: "wifi.exclamationmark.circle.fill")
                            .bold()
                            .imageScale(.large)
                            .symbolEffect(.pulse.wholeSymbol)
                            .padding()
                            .background {
                                Capsule()
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                    }
                    .transition(.scale)
                }

                if sonosService.systemState.notFound {
                    Button {
                        sonosService.monitor()
                    } label: {
                        Label("Discover Devices", systemImage: "waveform.badge.magnifyingglass")
                            .imageScale(.large)
                            .symbolEffect(.variableColor)
                            .padding()
                            .background {
                                Capsule()
                                    .foregroundStyle(.ultraThinMaterial)
                            }
                    }
                    .transition(.scale)
                }

                if !subscriptionService.subscription.isActive {
                    PaywallButtonView()
                        .padding(.horizontal)
                        .padding(.vertical, 8)
                        .transition(.scale)
                }
            }
        }
        .ignoresSafeArea(.keyboard, edges: .bottom)
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

