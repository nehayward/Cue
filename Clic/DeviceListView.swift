import SwiftUI
import SonosKit

struct DeviceListView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var superMember: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService

//    @Binding var current: GroupRoom?
    @Binding var selected: String?
    @State var isShowing: Bool = false

    var body: some View {
        @Bindable var alertService = alertService
        @Bindable var sonosService = sonosService

        NavigationSplitView {
            List ($sonosService.sorted, selection: $selected) { $group in
                Section {
                    VStack {
                        HStack(alignment: .top) {
//                            ArtworkView(group: $group)
//                                .frame(width: 72, height: 72)
                            ArtworkViewKing(group: $group)
                                .frame(width: 72, height: 72)
                            ZoneView(group: $group)
                            Spacer()
                            MediaControlsView(group: $group)
                        }
                        Divider()
                        VolumeControlView(group: $group)
                    }
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
            }
            .safeAreaInset(edge: .bottom) {
                if !sonosService.groups.isEmpty {
                    SceneView()
                        .padding()
                        .background {
                            Color.clear.allowsHitTesting(false)
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

            if !sonosService.networkMonitorService.isConnected {
                Text("Please connect to WiFi to find system")
                    .padding()
                    .background {
                        Capsule()
                            .foregroundStyle(.thinMaterial)
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
        }

    }
}


#Preview {
    DeviceListView(selected: .constant(nil))
        .environment(SonosService())
        .environment(SubscriptionService())
        .environment(AlertService())

}

