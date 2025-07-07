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
    
    @Environment(\.colorScheme) private var colorScheme
    
    @Binding var selected: String?

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    
    @State private var hoveredID: String? = nil
    
    private var listRowBackground: Color {
        #if targetEnvironment(macCatalyst)
        Color(UIColor.secondarySystemBackground)
        #else
        colorScheme == .light ? Color.white : Color(uiColor: .secondarySystemFill)
        #endif
    }

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
                                .transition(.asymmetric(
                                    insertion: .opacity,
                                    removal: .opacity.animation(.snappy(duration: 0))
                                ))
                                .padding(.horizontal, 12)
                        } else {
                            HStack(alignment: .top) {
                                ArtworkView(group: group)
                                    .frame(width: 72, height: 72)
                                ZoneView(group: group)
                                Spacer()
                                MediaControlsView(group: group)
                            }
                            .transition(.asymmetric(
                                insertion: .opacity,
                                removal: .opacity.animation(.snappy(duration: 0))
                            ))
                            .padding(.horizontal, 12)
                        }
                        VolumeControlView(group: group, delayDrag: true)
                    }
                    .animation(.spring, value: group.TVMode)
                    .tag(group.coordinatorID)
                    .listRowBackground(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(
                                group.coordinatorID == selected ? Color(uiColor: .systemFill) :
                                    hoveredID == group.coordinatorID ? Color(uiColor: .tertiarySystemFill) :
                                    listRowBackground
                            )
                    )
                    .onHover { isHovered in
                        if [.mac, .vision, .pad].contains(UIDevice.current.userInterfaceIdiom)  {
                            withAnimation(.interactiveSpring) {
                                hoveredID = isHovered ? group.coordinatorID : nil
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    .listRowInsets(EdgeInsets(top: 12, leading: 0, bottom: group.TVMode ? 12 : 10, trailing: 0))
                    .dropDestinationPlay(on: group)
                    .paywall(enabled(group: group))
                } else {
                    Text(group.coordinatorRoom.state.reason)
                        .selectionDisabled()
                        .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
                        .listRowBackground(Color(UIColor.secondarySystemBackground).clipShape(RoundedRectangle(cornerRadius: 16)))
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
#if targetEnvironment(macCatalyst)
                .foregroundStyle(.foreground)
                .font(.title2)
#endif
                .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
        }
        .animation(.interactiveSpring, value: sonosService.sorted)
        .animation(.interactiveSpring, value: sonosService.sortOption)
        .environment(\.defaultMinListRowHeight, 40)
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
                Picker("Sort by", systemImage:  "arrow.up.arrow.down.circle.fill", selection: $sonosService.sortOption) {
                    ForEach(SonosSortOption.allCases) { option in
                        Text(option.title)
                            .tag(option)
                    }
                }
            }
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
