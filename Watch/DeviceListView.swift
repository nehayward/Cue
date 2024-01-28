import CloudStorage
import SwiftUI
import SonosKit
import VibesDS

struct DeviceListView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Router.self) var router: Router
    @Environment(Popover.self) var popover: Popover
    @Binding var activeSubscription: Bool
    @Binding var selected: String?

    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []

    var body: some View {
        @Bindable var sonosService = sonosService
        @Bindable var router = router
        
        // MARK: Add Back for Debugging
//        let _ = Self._printChanges()
        NavigationSplitView {
            List (selection: $selected) {
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
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.sheet(to: .preferences)
                    } label: {
                        Image(systemName: "slider.vertical.3")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.sheet(to: .scenes)
                    } label: {
                        Image(systemName: "bolt.circle.fill")
                    }
                    Spacer()
                }
            }
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
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
            if popover.isShowing {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        Text(popover.text)
                            .animation(nil)
                    }
                    .transition(.opacity)
            }
        }
        .background(Color.clear)
        .animation(.interactiveSpring, value: sonosService.groups)
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
        .environment(Router())
        .withEnvironments()
}

#Preview("Active Subscription") {
    DeviceListView(activeSubscription: .constant(true), selected: .constant(nil))
        .environment(Router())
        .withEnvironments()
}
