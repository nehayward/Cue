import CloudStorage
import SwiftUI
import SonosKit
import VibesDS

struct DeviceListView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover
    @Binding var activeSubscription: Bool
    @Binding var selected: String?

    var body: some View {
        @Bindable var sonosService = sonosService

        NavigationSplitView {
            List (selection: $selected) {
                SceneView()
                    .listRowBackground(Color.clear)
                ForEach($sonosService.sorted) { $group in
                    DeviceCellView(group: $group)
                        .tag(group.coordinatorID)
                        .redacted(reason: enabled(group: group) ? [] : .placeholder)
                        .disabled(!enabled(group: group))
                        .selectionDisabled(!enabled(group: group))
                        .padding(.vertical)
                }
            }
            .listStyle(.carousel)
        } detail: {
            TabView {
                if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                    PlayerScreen(group: $sonosService.sorted[index])
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
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
        .animation(.spring, value: sonosService.isSearching)
        .onChange(of: selected) {
            if let selected, let index = sonosService.sorted.firstIndex(where: { $0.coordinatorID == selected }) {
                sonosService.selectedGroup = sonosService.sorted[index]
            } else {
                sonosService.selectedGroup = nil
            }
        }
        .overlay {
            if popOver.isShowing {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Text(popOver.text)
                            .animation(nil)
                    }
                    .transition(.opacity)
            }
        }
        .background(Color.clear)
        .onAppear {
            guard ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" else { return }
            sonosService.monitorWatch(useCache: true)
        }
//        .overlay {
//            VStack {
//                Text(!sonosService.sonosPulse.isCancelled ? "Running" : "Cancelled")
//                    .bold()
//                Spacer()
//            }
//            .ignoresSafeArea()
//        }
//        .overlay(alignment: .top) {
//            if sonosService.systemNotFound {
//                VStack {
//                    Text("Disconnected \(sonosService.isRunning ? "Running" : "Failed"), \(sonosService.lastKnownIP)")
//                        .bold()
//                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//                    Button {
//                        sonosService.monitorWatch()
//                    } label: {
//                        Text("Search for System")
//                            .bold()
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .foregroundStyle(.thickMaterial)
//                    .padding()
//                }
//                .background {
//                    Rectangle()
//                        .foregroundStyle(.thinMaterial)
//                        .ignoresSafeArea()
//                }
//            }
//
//            if sonosService.groups.isEmpty {
//                VStack {
//                    Text("Empty \(sonosService.isRunning ? "Running" : "Failed")")
//                        .bold()
//                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
//                    Button {
//                        sonosService.monitorWatch()
//                    } label: {
//                        Text("Search for System")
//                            .bold()
//                    }
//                    .buttonStyle(.borderedProminent)
//                    .foregroundStyle(.thickMaterial)
//                    .padding()
//                }
//                .background {
//                    Rectangle()
//                        .foregroundStyle(.thinMaterial)
//                        .ignoresSafeArea()
//                }
//            }
//        }
//        .animation(.smooth, value: sonosService.systemNotFound)
//        .animation(.smooth, value: sonosService.groups)
    }

    private func enabled(group: GroupRoom) -> Bool {
        if activeSubscription { return true }
        guard let index = sonosService.sorted.firstIndex(of: group) else { return false }
        return index < 1
    }
}

#Preview {
    DeviceListView(activeSubscription: .constant(false), selected: .constant(nil))
        .environment(SonosService())
        .environment(Popover())
}

#Preview("Active Subscription") {
    DeviceListView(activeSubscription: .constant(true), selected: .constant(nil))
        .environment(SonosService())
        .environment(Popover())
}
