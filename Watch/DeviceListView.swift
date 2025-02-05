import CloudStorage
import SwiftUI
import SonosKitMini
import VibesDS

struct DeviceListView: View {
    @Environment(SonosMiniService.self) var sonosService: SonosMiniService
    @Environment(Router.self) var router: Router
    @Environment(Popover.self) var popover: Popover
    @Binding var activeSubscription: Bool
    @Binding var selected: String?

//    @CloudStorage("com.clic.scenes") var scenes: [SonosScene] = []
    
    private var filteredDeviceBindings: [SonosDevice] {
        sonosService.sortedNowPlaying.filter(\.isVisible)
    }

    var body: some View {
        @Bindable var router = router
        
//         MARK: Add Back for Debugging
//        let _ = Self._printChanges()
        NavigationSplitView {
            List (selection: $selected) {
                ForEach(filteredDeviceBindings) { device in
                    DeviceCellView(id: device.id)
                        .frame(maxHeight: 200)
                        .transition(.asymmetric(
                            insertion: .scale(scale: 0.9)
                                .combined(with: .opacity),
                            removal: .scale(scale: 0.4)
                                .combined(with: .opacity)
                        ))
                        .id(device.id)
                        .redacted(reason: enabled(device) ? [] : .placeholder)
                        .disabled(!enabled(device))
                        .selectionDisabled(!enabled(device))
                        .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 0))
                }
            }
            .animation(.interactiveSpring, value: filteredDeviceBindings)
            .listStyle(.carousel)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.sheet(to: .preferences)
                    } label: {
                        Image(systemName: "switch.2")
                    }
                }
                
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        router.sheet(to: .scenes)
                    } label: {
                        Image(systemName: "bolt.fill")
                    }
                    Spacer()
                }
            }
            .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        } detail: {
            if let selected {
                PlayerScreen(id: selected)
            } else {
                Text("Group No Longer Available")
                    .navigationBarTitleDisplayMode(.inline)
            }
        }
        .overlay {
            if filteredDeviceBindings.isEmpty {
                Label("Searching", systemImage: "waveform.badge.magnifyingglass")
                    .imageScale(.large)
                    .symbolEffect(.variableColor)
                    .padding()
                    .background {
                        Capsule()
                            .foregroundStyle(.ultraThinMaterial)
                    }
                    .transition(.opacity)
            }
        }
        .overlay {
            if popover.isShowing {
                Rectangle()
                    .ignoresSafeArea()
                    .foregroundStyle(.ultraThinMaterial)
                    .overlay {
                        VStack {
                            Text(popover.text)
                                .fontDesign(.rounded)
                                .font(.title)
                                .bold()
                            let value = Double(popover.text) ?? 0.0
                            VibeSlider(value: .constant(value), in: 0...100, step: 1, baseHeight: 12, delayDrag: false)
                                .padding(.horizontal)
                        }
                    }
                    .transition(.opacity)
       
            }
        }
    }

    private func enabled(_ device: SonosDevice) -> Bool {
        if activeSubscription { return true }
        guard let index = sonosService.sorted.firstIndex(of: device) else { return false }
        return index < 1
    }
}
