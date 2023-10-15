import SwiftUI
import SonosKit
import VibesDS
import SubscriptionKit
import RevenueCat
import RevenueCatUI

struct DeviceListMainView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var subscriptionService: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService

    @Binding var selected: String?
    @State var isShowing: Bool = false
    @State var showSettings: Bool = false
    @State private var showPaywall: Bool = false

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService

        NavigationSplitView {
            List ($sonosService.sorted, selection: $selected) { $group in
                Section {
                    VStack {
                        if group.tvMode {
                            TVModeViewCell(group: $group)
                        } else {
                            HStack(alignment: .top) {
                                ArtworkViewKing(group: $group)
                                    .frame(width: 72, height: 72)
                                ZoneView(group: $group)
                                Spacer()
                                MediaControlsView(group: $group)
                            }
                            .padding(.bottom, 4)
                        }
                        Divider()
                        VolumeControlView(group: $group)
                    }
                    .tag(group.coordinatorID)
                } header: {
                    HStack {
                        Image(systemName: "hifispeaker.fill")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .font(.body)
                }
                .tag(group.coordinatorID)
                .headerProminence(.increased)
                .redacted(reason: enabled(group: group) ? [] : .placeholder)
                .disabled(!enabled(group: group))
                .selectionDisabled(!enabled(group: group))
            }
            .safeAreaInset(edge: .bottom) {
                if !subscriptionService.subscription.isActive {
                    Button {
                        showPaywall = true
                    } label: {
                        Text("Show all devices (\(sonosService.groups.count))")
                            .fontDesign(.rounded)
                            .bold()
                            .foregroundStyle(Color.accentColor.gradient)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(.thickMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding()
                            .shadow(radius: 16, x: 0, y: 2)
                    }
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
            .safeAreaInset(edge: .bottom) {
                if !sonosService.groups.isEmpty && subscriptionService.subscription.isActive {
                    VStack{
                        SceneView()
                            .padding(12)
                    }
                }
            }
//            .overlay(alignment: .topTrailing) {
//                Button {
//                    showSettings = true
//                } label: {
//                    Image(systemName: "gear")
//                        .resizable()
//                        .frame(width: 24, height: 24)
//                        .padding([.trailing, .top])
//                }
//                .padding()
//                .frame(maxWidth: .infinity, alignment: .trailing)
//                .background(.thinMaterial)
//                .ignoresSafeArea()
//            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showSettings = true
                    } label: {
                        Image(systemName: "gear")
                    }
                }
            }
//            VStack {
//                SceneView(show: $isShowing)
//                //                    .listRowBackground(Color.clear)
//                Slider(value: .constant(0))
//            }
//            .backgroundStyle(.thinMaterial)
        } detail: {
            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                LargePlayerView(group: $sonosService.sorted[index], selected: $selected)
            }
        }
//        .onChange(of: current) {
//            guard let current else {
//                sonosService.selectedGroup = nil
//                return
//            }
//            sonosService.selectedGroup = current
//        }
        .onChange(of: selected) {
            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                sonosService.selectedGroup = sonosService.sorted[index]
            } else {
                sonosService.selectedGroup = nil
                selected = nil
            }
        }
        .animation(.spring, value: sonosService.isSearching)
        // MARK: Debug
//        .overlay {
//                VStack {
//                    Text(sonosService.networkMonitorService.isConnected ? "Connected" : "Disconnect")
//                    Text(!sonosService.monitorTask.isCancelled ? "Running" : "Cancelled")
//                        .bold()
//                    Spacer()
//                }
//                .ignoresSafeArea()
//                .padding(.top, 30)
//        }
        .safeAreaInset(edge: .bottom) {
            if sonosService.permissionsDenied {
                Button {
                    // MARK: Settings Action
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                } label: {
                    Text("Local Network Permission Needed")
                        .padding()
                        .background {
                            Capsule()
                                .foregroundStyle(.thinMaterial)
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                .padding()
            }

            if sonosService.systemNotFound {
                Button {
                    sonosService.monitor()
                } label: {
                    Text("Search")
                        .bold()
                        .padding()
                        .background {
                            Capsule()
                                .foregroundStyle(.thinMaterial)
                        }
                }
                .transition(.move(edge: .bottom).combined(with: .scale(0.8)))
                .padding()
            }

            if sonosService.isSearching && sonosService.groups.isEmpty {
                Label("Searching", systemImage: "waveform.badge.magnifyingglass")
                    .imageScale(.large)
                    .symbolEffect(.variableColor)
                    .padding()
                    .background {
                        Capsule()
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    .transition(.push(from: .bottom).combined(with: .scale))
            }
        }
        .safeAreaInset(edge: .top) {
            if alertService.alert.isShowing {
                PillView()
                    .environment(alertService)
            }
            if !sonosService.networkMonitorService.isConnected {
                Label {
                    Text("Connect to WiFi to find system")
                } icon: {
                    Image(systemName: "wifi.slash")
                }
                .bold()
                .padding()
                .background {
                    Capsule()
                        .foregroundStyle(.thinMaterial)
                }
                .transition(.move(edge: .top).combined(with: .scale(0.8)))
                .padding()
                .offset(y: 50)
            }
        }
        .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
        .animation(.spring, value: sonosService.systemNotFound)
        .animation(.spring, value: sonosService.permissionsDenied)
        .animation(.spring, value: alertService.alert.isShowing)
        .onAppear {
            let thumbImage = UIImage()
            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
        }
        .animation(.interactiveSpring, value: sonosService.groups)
        .task {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitor()
//            showSettings = true
        }
        .sheet(isPresented: $showSettings) {
            PreferenceScreen()
        }
//        .sheet(isPresented: $showSettings) {
//            PaywallScreen()
//        }
    }

    private func enabled(group: GroupRoom) -> Bool {
        if subscriptionService.subscription.isActive { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}


#Preview {
    DeviceListMainView(selected: .constant(nil))
        .environment(SonosService())
        .environment(SubscriptionService())
        .environment(AlertService())
}

