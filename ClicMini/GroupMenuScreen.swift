import Foundation
import SonosKitMini
import SwiftUI

struct GroupMenuScreen: View {
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var menuVisibilityService = MenuVisibilityService.shared
    @State private var isLoading: Bool = false
    @State private var scenes: [SonosScene] = []
    @State private var isVisible = false
    @State private var expandedGroupIDs: Set<String> = []

    private var filteredDeviceBindings: [Binding<SonosDevice>] {
        sonosServiceMini.sortedNowPlaying
            .enumerated()
            .filter { !$0.element.isHidden && $0.element.state == .active }
            .map { index, _ in
                $sonosServiceMini.sortedNowPlaying[index]
            }
    }

    var body: some View {
        mainContent
            .fontDesign(.rounded)
            .padding(.vertical)
            .environment(sonosServiceMini)
            .task {
                try? await SonosMiniService.shared.loadWatch(useCache: true)
            }
            .onAppear {
                loadScenes()
                isVisible = true
                menuVisibilityService.setMenuVisible(true)
            }
            .onDisappear {
                isVisible = false
                menuVisibilityService.setMenuVisible(false)
            }
    }

    private func loadScenes() {
        guard let data = NSUbiquitousKeyValueStore.default.data(forKey: "com.clic.scenes"),
              let decoded = try? JSONDecoder().decode([SonosScene].self, from: data) else { return }
        scenes = decoded
    }

    private var screenMaxHeight: Double {
        (NSScreen.main?.visibleFrame.height ?? 800) * 0.75
    }

    private var contentIdealHeight: Double {
        filteredDeviceBindings.reduce(0.0) { total, $device in
            let groupExtra: Double = device.rooms.isEmpty ? 0.0 : 30.0
            let expandedExtra: Double = expandedGroupIDs.contains(device.id)
                ? 6.0 + Double(device.allDevices.count) * 70.0
                : 0.0
            return total + 150.0 + groupExtra + expandedExtra
        }
    }

    var mainContent: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(filteredDeviceBindings) { $device in
                    GroupItemView(isVisible: $isVisible, device: $device, expandedGroupIDs: $expandedGroupIDs)
                }
            }
            .padding(.horizontal, 12)
        }
        .frame(minWidth: 400, minHeight: min(contentIdealHeight, screenMaxHeight))
        .onAppear {
            Task {
                isLoading = true
                try? await sonosServiceMini.loadWatch(useCache: true)
                isLoading = false
            }
            Task {
                // Re-fetch queueTotal for visible speakers — the popover may have been
                // closed while the user reordered/trimmed the queue, and those mutations
                // don't trigger a metadata event.
                await sonosServiceMini.refreshQueueTotals()
            }
        }
        .overlay { GroupMenuEmptyOverlay(isLoading: isLoading, isEmpty: filteredDeviceBindings.isEmpty) }
        .onChange(of: filteredDeviceBindings.map(\.wrappedValue.id)) { _, ids in
            expandedGroupIDs.formIntersection(ids)
        }
        .animation(.snappy, value: isLoading)
        .animation(.snappy, value: sonosServiceMini.devices.map(\.isPlaying))
        .safeArea(edge: .bottom) {
            GroupMenuBottomBar(scenes: scenes)
        }
    }
}

// MARK: - Extracted Subviews

fileprivate struct GroupMenuEmptyOverlay: View {
    let isLoading: Bool
    let isEmpty: Bool

    var body: some View {
        if isLoading, isEmpty {
            ProgressView()
                .padding(.vertical)
                .controlSize(.small)
                .transition(.opacity)
        } else if !isLoading, isEmpty {
            Link(destination: URL(string: "clic://")!) {
                Text("Sonos System not found, Launch Clic")
                    .font(.title2)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .padding(.vertical)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .transition(.opacity)
        }
    }
}

fileprivate struct GroupMenuBottomBar: View {
    let scenes: [SonosScene]

    var body: some View {
        HStack {
            if !scenes.isEmpty {
                Menu {
                    ForEach(scenes) { scene in
                        SceneButtonView(scene: scene)
                    }
                } label: {
                    Image(systemName: "bolt.fill")
                        .font(.title)
                }
                .menuIndicator(.hidden)
                .modifier(SettingsMenuStyleModifier())
            }
            SettingsMenuView()
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .padding(.horizontal)
    }
}

// MARK: - Group Header

struct GroupHeader: View {
    let device: SonosDevice
    @State private var miniSettingsService = MiniSettingsService.shared
    @State private var sonosServiceMini = SonosMiniService.shared
    @State private var showGrouping: Bool = false
    @State private var pendingGroupIDs: Set<String> = []
    @State private var pendingUngroupIDs: Set<String> = []

    var body: some View {
        HStack {
            Text(device.nameWithCount)
            Spacer()
            GroupHeaderGroupButton(
                device: device,
                showGrouping: $showGrouping,
                pendingGroupIDs: $pendingGroupIDs,
                pendingUngroupIDs: $pendingUngroupIDs,
                allSpeakers: allSpeakers,
                groupedIDs: groupedIDs
            )
            GroupHeaderPinButton(deviceId: device.id)
            GroupHeaderBatteryView(battery: device.battery)
        }
        .fontDesign(.rounded)
        .foregroundStyle(.foreground)
        .font(.title2)
    }

    private var groupedIDs: Set<String> {
        Set(device.allDevices.map(\.id))
    }

    private var allSpeakers: [(speaker: SonosDevice, isGrouped: Bool)] {
        var seen = Set<String>()
        var result: [(speaker: SonosDevice, isGrouped: Bool)] = []
        let allSystemSpeakers = sonosServiceMini.devices.flatMap(\.allDevices)

        for speaker in allSystemSpeakers {
            guard speaker.state == .active, seen.insert(speaker.id).inserted else { continue }
            let isInGroup = groupedIDs.contains(speaker.id)
            let visuallyGrouped = isInGroup
                ? !pendingUngroupIDs.contains(speaker.id)
                : pendingGroupIDs.contains(speaker.id)
            result.append((speaker: speaker, isGrouped: visuallyGrouped))
        }

        return result.sorted { $0.speaker.name < $1.speaker.name }
    }
}

fileprivate struct GroupHeaderGroupButton: View {
    let device: SonosDevice
    @Binding var showGrouping: Bool
    @Binding var pendingGroupIDs: Set<String>
    @Binding var pendingUngroupIDs: Set<String>
    let allSpeakers: [(speaker: SonosDevice, isGrouped: Bool)]
    let groupedIDs: Set<String>

    var body: some View {
        Button {
            showGrouping.toggle()
        } label: {
            Image(systemName: "hifispeaker.arrow.forward.fill")
                .foregroundStyle(.secondary)
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Group with...")
        .popover(isPresented: $showGrouping, arrowEdge: .bottom) {
            popoverContent
        }
    }

    private var popoverContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Group Speakers")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.top, 4)

            Divider()
                .padding(.horizontal, 4)

            ForEach(allSpeakers, id: \.speaker.id) { item in
                GroupingRow(
                    name: item.speaker.name,
                    subtitle: nil,
                    isGrouped: item.isGrouped,
                    isEnabled: item.speaker.id != device.id
                ) {
                    toggleGrouping(for: item)
                }
            }
        }
        .fontDesign(.rounded)
        .padding(6)
        .frame(minWidth: 260)
        .animation(.snappy, value: pendingGroupIDs)
        .animation(.snappy, value: pendingUngroupIDs)
        .onChange(of: groupedIDs) {
            pendingGroupIDs = []
            pendingUngroupIDs = []
        }
        .onAppear {
            pendingGroupIDs = []
            pendingUngroupIDs = []
        }
    }

    private func toggleGrouping(for item: (speaker: SonosDevice, isGrouped: Bool)) {
        if item.isGrouped {
            pendingUngroupIDs.insert(item.speaker.id)
            Task {
                await SonosMiniService.shared.ungroup(device: item.speaker)
                try? await Task.sleep(for: .milliseconds(500))
            }
        } else {
            pendingGroupIDs.insert(item.speaker.id)
            Task {
                await SonosMiniService.shared.group(rooms: [item.speaker], to: device.id)
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }
}

fileprivate struct GroupHeaderPinButton: View {
    let deviceId: String
    @State private var miniSettingsService = MiniSettingsService.shared

    private var isPinned: Bool {
        miniSettingsService.isSpeakerPinned(id: deviceId)
    }

    var body: some View {
        Button {
            if isPinned {
                miniSettingsService.unpinSpeaker()
            } else {
                miniSettingsService.pinSpeaker(id: deviceId)
            }
        } label: {
            Image(systemName: isPinned ? "pin.fill" : "pin")
                .foregroundStyle(isPinned ? AnyShapeStyle(.accent.gradient) : AnyShapeStyle(.secondary))
                .frame(width: 32, height: 32)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(isPinned ? "Unpin from menu bar" : "Pin to menu bar")
    }
}

fileprivate struct GroupHeaderBatteryView: View {
    let battery: Battery?

    var body: some View {
        if let battery {
            Text((battery.percentage / 100), format: .percent)
                .foregroundStyle(.secondary)
            if battery.chargingState == .charging {
                Image(systemName: "battery.100percent.bolt")
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
            }
        }
    }
}

// MARK: - Scene Button

struct SceneButtonView: View {
    let scene: SonosScene
    @State private var sonosServiceMini = SonosMiniService.shared

    private var sceneDetail: Text {
        var parts: [Text] = []

        if let title = scene.playableContent?.title, !title.isEmpty {
            parts.append(Text(title))
        }

        if scene.volumeOnly {
            parts.append(Text("Volume only"))
        }

        if let playMode = scene.playMode {
            if playMode.isShuffleEnabled { parts.append(Text("Shuffle")) }
            if playMode.isRepeatOneEnabled { parts.append(Text("Repeat one")) }
            else if playMode.isRepeatAllEnabled { parts.append(Text("Repeat all")) }
        }

        if let sleepTimer = scene.sleepTimer {
            parts.append(Text("Sleep \(sleepTimer.formatted(.units(width: .abbreviated)))"))
        }

        let roomDetails = scene.rooms.map { "\($0.name) \(Int($0.volume))%" }
        if !roomDetails.isEmpty {
            parts.append(Text(roomDetails.joined(separator: ", ")))
        }

        let separator = Text(" · ")
        return parts.enumerated().reduce(Text("")) { result, item in
            item.offset == 0 ? item.element : result + separator + item.element
        }
    }

    var body: some View {
        Button {
            Task {
                try? await sonosServiceMini.runScene(scene)
            }
        } label: {
            Text(scene.name)
            sceneDetail
        }
    }
}

// MARK: - Helpers

private struct GroupingRow: View {
    let name: String
    let subtitle: String?
    let isGrouped: Bool
    let isEnabled: Bool
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button {
            guard isEnabled else { return }
            action()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
                Image(systemName: isGrouped ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(isGrouped ? (isEnabled ? .primary : .tertiary) : .secondary)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background {
                RoundedRectangle(cornerRadius: 6)
                    .foregroundStyle(isHovered ? AnyShapeStyle(HierarchicalShapeStyle.quaternary) : AnyShapeStyle(Color.clear))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .onHover { isHovered = $0 }
    }
}

struct PreferencesCogButton: View {
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(isHovered ? .accentColor : .secondary)
                .padding(8)
                .background(
                    Circle()
                        .fill(isHovered ? Color.accentColor.opacity(0.1) : Color.clear)
                )
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Preferences")
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
    }
}

private struct BottomSettingsModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .safeAreaBar(edge: .bottom) {
                    HStack {
                        SettingsMenuView()
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal)
                }
        } else {
            content
                .overlay(alignment: .bottomTrailing) {
                    SettingsMenuView()
                        .padding(12)
                }
        }
    }
}

extension View {
    @ViewBuilder
    func safeArea<V>(edge: VerticalEdge, @ViewBuilder content: () -> V) -> some View where V : View {
        if #available(iOS 26.0, macOS 26, *) {
            self
                .safeAreaBar(edge: edge, content: content)
        } else {
            self
                .safeAreaInset(edge: edge, content: content)
        }
    }
}
