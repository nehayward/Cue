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
        
        List ($sonosService.sorted, selection: $selected) { $group in
            Section {
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
                    VolumeControlView(group: $group, touchDelay: 0.05)
                        .frame(height: 24)
                }
                .tag(group.coordinatorID)
                .listRowBackground(group.coordinatorID == selected ? Color(uiColor: .systemFill).clipShape(RoundedRectangle(cornerRadius: 12)) : nil)
                .foregroundStyle(.primary)
                .listRowInsets(EdgeInsets(top: 12, leading: 12, bottom: 10, trailing: 12))
            } header: {
                Text(group.nameWithCount)
                    .fontDesign(.rounded)
                    .headerProminence(.increased)
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 8, trailing: 0))
            }
            .redacted(reason: enabled(group: group) ? [] : .placeholder)
            .disabled(!enabled(group: group))
            .selectionDisabled(!enabled(group: group))
        }
        .animation(.interactiveSpring, value: sonosService.groups)
        .onChange(of: sonosService.sorted) { 
            if selected == nil {
                selected = sonosService.sorted.first?.coordinatorID
            }
        }
        #if targetEnvironment(macCatalyst)
        .navigationBarHidden(true)
        .listStyle(.sidebar)
        #else
        .listStyle(.insetGrouped)
        #endif
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentedSheet = .settings
                } label: {
                    Image(systemName: "slider.vertical.3")
                }
            }
        }
        .overlay(alignment: .bottom) {
            VStack {
                if sonosService.systemState.permissionDenied {
                    Button {
                        // MARK: Settings Action
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
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
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 24) {
                Spacer()
                if subscriptionService.subscription.isActive {
                    Button {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.sheet(to: .scenes)
                    } label: {
                        Image(systemName: "wand.and.stars.inverse")
                            .resizable()
                            .foregroundStyle(.accent.gradient)
                            .frame(width: 24, height: 24)
                    }
                }

                Image(systemName: "sparkle.magnifyingglass")
                    .resizable()
                    .foregroundStyle(.accent.gradient)
                    .frame(width: 24, height: 24)
                    .onTapGesture {
                        HapticManager.shared.fireHaptic(.buttonPress)
                        router.presentedSheet = .search()
                    }
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5)
                            .onEnded { _ in
                                HapticManager.shared.fireHaptic(.buttonPress)
                                router.presentedSheet = .search(instant: true)
                            }
                    )
                    .contentShape(Capsule())
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(.thinMaterial)
            .ignoresSafeArea(.keyboard)
        }
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

