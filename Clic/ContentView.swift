import SwiftUI
import SonosKit

struct ContentView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(SubscriptionService.self) var superMember: SubscriptionService
    @Environment(AlertService.self) var alertService: AlertService

    @Binding var selected: String?
    @State var isShowing: Bool = false

    var body: some View {
        @Bindable var alert = alertService.alert

        NavigationSplitView {
            List (sonosService.sorted, selection: $selected) { group in
                Section {
                    VStack {
                        HStack(alignment: .top) {
                            ArtworkView(group: group)
                                .frame(width: 72, height: 72)
                            ZoneView(group: group)
                            Spacer()
                            MediaControlsView(group: group)
                        }
                        Divider()
                        VolumeControlView(roomGroup: group)
                    }
                } header: {
                    HStack {
                        Image(systemName: "hifispeaker")
                        Text(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
                    }
                    .fontDesign(.rounded)
                    .font(.body)
                }
                .tag(group.coordinatorID)
                .headerProminence(.increased)
            }
//            VStack {
//                SceneView(show: $isShowing)
//                //                    .listRowBackground(Color.clear)
//                Slider(value: .constant(0))
//            }
//            .backgroundStyle(.thinMaterial)
        } detail: {
            if selected != nil, let group = sonosService.groups.first(where: { group in
                group.coordinatorID == selected! }) {
                LargePlayerView(group: group)
            }
        }
        .onChange(of: selected) {
            guard let selected, superMember.isEnabled else { return }
            let selectedGroup = sonosService.groups.first(where: { room in
                room.coordinatorID == selected
            })

            guard let selectedGroup else { return }
            sonosService.selectedGroup = selectedGroup
        }
        .animation(.spring, value: sonosService.isSearching)
        .task {
            sonosService.monitor()
            await superMember.setup()
        }
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

            if sonosService.isSearching {
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
                PillView(alert: alertService.alert)
                    .animation(.spring, value: alertService.alert.isShowing)
            }
        }
        .animation(.bouncy, value: sonosService.networkMonitorService.isConnected)
        .animation(.spring, value: sonosService.systemNotFound)
        .animation(.spring, value: sonosService.permissionsDenied)
        .onAppear {
            let thumbImage = UIImage()
            UISlider.appearance().setThumbImage(thumbImage, for: .normal)
        }
        .animation(.smooth, value: sonosService.groups)
    }
}

#Preview {
    ContentView(selected: .constant(nil))
        .environment(SonosService())
        .environment(SubscriptionService())
}

