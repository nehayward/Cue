import CloudStorage
import OrderedCollections
import Defaults
import SwiftUI
import SonosKit
import NukeUI
import VibesDS

struct SelectGroupView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(SonosService.self) private var sonosService
    @Environment(SelectedGroupService.self) private var selectedGroupService
    
    var content: PlayableContent?
    var defaultPosition: QueuePosition = .now
    @State private var filter: String = ""
    @State private var groupVolume: Double = 0
    @State private var selections = Set<String>()
    @State private var selectedPosition: QueuePosition = .now
    /// Device is the starting destination; picking rooms turns it off. Restored
    /// from — and saved back to — the destination the share extension shares.
    @State private var playOnThisDevice = true

    var onSelection: ((GroupRoom) async throws -> Void)? = nil
    var onQueueSelection: ((GroupRoom, QueuePosition) async throws -> Void)? = nil

    /// Whether the queue-position selector applies — shown when a caller wires
    /// `onQueueSelection` (a real queue flow) and the content can be queued
    /// (i.e. not radio). Grouping/radio callers that only pass `onSelection`
    /// don't get a non-functional picker.
    private var showsQueuePositions: Bool {
        onQueueSelection != nil && (content.map { !$0.content.type.isRadio } ?? false)
    }

    /// Device is only on the table for a real queue flow (the grouping and
    /// radio callers pass `onSelection` alone) and content the local queue can
    /// actually take — Apple and Plex, never Spotify or a station.
    private var canPlayOnDevice: Bool {
        guard onQueueSelection != nil, let content else { return false }
        return LocalPlaybackService.shared.canPlayAnywhereLocally(content)
    }

    private var deviceSelected: Bool {
        canPlayOnDevice && playOnThisDevice
    }

    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }
    
    private var allSelected: Bool {
        !activeRooms.isEmpty && selections.count == activeRooms.count
    }
    
    private var playingRooms: [Room] {
        activeRooms.filter { sonosService.playbackRoom(for: $0).isPlaying }
    }

    private var otherRooms: [Room] {
        activeRooms.filter { !sonosService.playbackRoom(for: $0).isPlaying }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let content {
                    PlayableContentRowView(item: content)
                        .padding([.top, .horizontal])
                }

                if showsQueuePositions {
                    Picker("Play", selection: $selectedPosition) {
                        ForEach([QueuePosition.now, .next, .end, .replace]) { position in
                            Text(position.shortTitle).tag(position)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                ScrollView {
                    LazyVStack(spacing: 8) {
                        existingGroupsScroll
                        Divider()
                        if canPlayOnDevice {
                            deviceRow
                        }
                        everywhereButton
                        
                        // Playing rooms first, then others
                        ForEach(playingRooms) { room in
                            roomRow(room: room)
                        }
                        
                        ForEach(otherRooms) { room in
                            roomRow(room: room)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .contentMargins(.bottom, EdgeInsets(top: 0, leading: 0, bottom: 150, trailing: 0), for: .scrollContent)
                .overlay(alignment: .bottom) {
                    VStack {
                        HStack {
                            Button {
                                groupVolume = max(0, groupVolume - 1)
                            } label: {
                                Image(systemName: "minus")
                                    .frame(width: 24, height: 24)
                                    .bold()
                            }
                            .tint(.primary)
                            .buttonStyle(.liveActivity)
                            .buttonRepeatBehavior(.enabled)
                            VibeSlider(value: $groupVolume, step: 1, showValue: true)
                            Button {
                                groupVolume = min(100, groupVolume + 1)
                            } label: {
                                Image(systemName: "plus")
                                    .frame(width: 24, height: 24)
                                    .bold()
                            }
                            .tint(.primary)
                            .buttonStyle(.liveActivity)
                            .buttonRepeatBehavior(.enabled)
                        }
                        .frame(height: 20)
                        .padding(.bottom)
                        Button {
                            if deviceSelected {
                                playHere()
                                return
                            }
                            Task {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                let selectedRooms = activeRooms.filter { room in
                                    selections.contains(room.id)
                                }
                                guard let newGroup = await sonosService.speedGroup(rooms: selectedRooms) else {
                                    print("Failed!")
                                    return
                                }
                                withAnimation {
                                    dismiss()
                                } completion: {
                                    Task {
                                        selectedGroupService.group = newGroup
                                        PlayDestination.group(newGroup.coordinatorID).remember()
                                        for room in selectedRooms {
                                            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(groupVolume))
                                            await sonosService.setRoomMute(IP: room.ip, mute: false)
                                        }
                                        if let onQueueSelection {
                                            try await onQueueSelection(newGroup, selectedPosition)
                                        } else {
                                            try await onSelection?(newGroup)
                                        }
                                        try await Task.sleep(for: .seconds(1))
                                        await sonosService.snapShotGroup(ip: newGroup.ip)
                                    }
                                }
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "play.fill")
                                Text(showsQueuePositions ? selectedPosition.title : "Play")
                                    .contentTransition(.identity)
                                if deviceSelected {
                                    Text("on This Device")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .bold()
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .foregroundStyle(.accent)
                            .background {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.accentColor.opacity(0.15))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                                    }
                            }
                        }
                        .buttonStyle(.plain)
                        .transition(.slide)
                        .disabled(!canCommit)
                        .opacity(canCommit ? 1 : 0.4)
                        .animation(.interactiveSpring, value: canCommit)
                    }
                    .padding()
                    .background {
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(.thinMaterial)
                            .ignoresSafeArea(edges: .bottom)
                    }
                }
            }
            .background(.regularMaterial)
        }
        .foregroundStyle(.primary)
        .fontDesign(.rounded)
        .task {
            selectedPosition = defaultPosition
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load(useCache: true)
            }
            restoreDestination()
        }
        .addDismiss {
            dismiss()
        }
        .animation(.interactiveSpring, value: sonosService.sorted)
        .animation(.interactiveSpring, value: selections)
        .animation(.interactiveSpring, value: playingRooms.map(\.id))
        .animation(.interactiveSpring, value: activeRooms.map {
            let playbackRoom = sonosService.playbackRoom(for: $0)
            return "\($0.id)-\(playbackRoom.isPlaying)-\(playbackRoom.track.name)"
        })
    }
    
    @ViewBuilder
    private func roomRow(room: Room) -> some View {
        // Grouped rooms hear the coordinator's stream, so show its track —
        // a member room's own `track` goes stale once it joins a group.
        let playbackRoom = sonosService.playbackRoom(for: room)
        Menu {
            if !playbackRoom.track.name.isEmpty {
                Section {
                    Label(playbackRoom.track.name, systemImage: "music.note")
                    if !playbackRoom.track.artist.isEmpty {
                        Label(playbackRoom.track.artist, systemImage: "person.fill")
                    }
                }
            }
            
            Section {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    playOnThisDevice = false
                    if selections.contains(room.id) {
                        selections.remove(room.id)
                    } else {
                        selections.insert(room.id)
                        groupVolume = room.volume
                    }
                } label: {
                    Label {
                        Text(selections.contains(room.id) ? "Deselect" : "Select")
                    } icon: {
                        Image(systemName: selections.contains(room.id) ? "circle" : "checkmark.circle.fill" )
                            .font(.title3)
                            .symbolRenderingMode(.hierarchical)
                            .contentTransition(.symbolEffect(.replace))
                            .foregroundStyle(selections.contains(room.id) ? Color.accentColor : .primary.opacity(0.7))
                    }
                }
                
                Button {
                    Task {
                        await sonosService.setRoomMute(IP: room.ip, mute: !room.isMuted)
                    }
                } label: {
                    Label(room.isMuted ? "Unmute" : "Mute", systemImage: room.isMuted ? "speaker.wave.2.fill" : "speaker.slash.fill")
                }
            }
        } label: {
            let isSelected = selections.contains(room.id)
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .font(.body.weight(.semibold))

                    if !playbackRoom.track.name.isEmpty {
                        Text(playbackRoom.track.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(playbackRoom.isPlaying ? .accent : .secondary)
                    }
                }

                Spacer(minLength: 4)

                if room.isMuted {
                    Image(systemName: "speaker.slash.fill")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(room.volume))")
                    .font(.footnote.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 22)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(Capsule().fill(.quaternary))

                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                        .opacity(isSelected ? 0 : 1)
                    Circle()
                        .fill(Color.accentColor)
                        .opacity(isSelected ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .opacity(isSelected ? 1 : 0)
                }
                .frame(width: 26, height: 26)
                .animation(.interactiveSpring, value: isSelected)
            }
            .fontDesign(.rounded)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(isSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
        } primaryAction: {
            HapticManager.shared.fireHaptic(.selection)
            playOnThisDevice = false
            if selections.contains(room.id) {
                selections.remove(room.id)
            } else {
                selections.insert(room.id)
                if groupVolume.isZero {
                    groupVolume = room.volume
                }
            }
        }
        .padding(.horizontal)
    }
    
    var filteredAndSortedGroups: [GroupRoom] {
        let filtered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) != nil }
        let nonFiltered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) == nil }
        return (filtered + nonFiltered).sorted { $0.coordinatorRoom.isPlaying && !$1.coordinatorRoom.isPlaying }
    }
    
    /// The existing multi-room groups, as one-tap shortcuts. Extracted from
    /// `body` — inline, the whole scene stopped type-checking in reasonable
    /// time once the Device row was added to it.
    private var existingGroupsScroll: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(sonosService.groups.filter { $0.rooms.count > 1 }) { group in
                    Button {
                        play(group: group)
                    } label: {
                        groupCard(group)
                    }
                }
            }
            .padding(.horizontal)
        }
        .padding(.top)
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
    }

    private func groupCard(_ group: GroupRoom) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(group.nameWithCount)
                    .fontWeight(.semibold)
                    .lineLimit(1)

                if !group.coordinatorRoom.track.name.isEmpty {
                    Text(group.coordinatorRoom.track.name)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(group.coordinatorRoom.isPlaying ? .accent : .secondary)
                }
            }

            Spacer()

            Text("\(Int(group.groupVolume))")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.primary.opacity(0.06))
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, _ in
            length / 1.75
        }
    }

    private var everywhereButton: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            playOnThisDevice = false
            if allSelected {
                selections.removeAll()
            } else {
                for room in activeRooms {
                    if groupVolume.isZero {
                        groupVolume = room.volume
                    }
                    selections.insert(room.id)
                }
            }
        } label: {
            HStack(spacing: 10) {
                Text(allSelected ? "Deselect All" : "Everywhere")
                    .fontWeight(.bold)
                    .contentTransition(.identity)
                Spacer(minLength: 4)
                if !selections.isEmpty {
                    Text("\(selections.count) of \(activeRooms.count)")
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .transaction { $0.animation = nil }
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .foregroundStyle(.accent)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(allSelected ? 0.22 : 0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Color.accentColor.opacity(0.55), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .fontDesign(.rounded)
        .padding(.horizontal)
    }

    private var canCommit: Bool {
        deviceSelected || !selections.isEmpty
    }

    private var deviceRow: some View {
        Button {
            HapticManager.shared.fireHaptic(.selection)
            playOnThisDevice = true
            selections.removeAll()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "iphone.radiowaves.left.and.right")
                    .font(.title3)
                    .foregroundStyle(deviceSelected ? Color.accentColor : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text("This Device")
                        .font(.body.weight(.semibold))
                    Text("Play here instead of a speaker")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.35), lineWidth: 2)
                        .opacity(deviceSelected ? 0 : 1)
                    Circle()
                        .fill(Color.accentColor)
                        .opacity(deviceSelected ? 1 : 0)
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.black)
                        .opacity(deviceSelected ? 1 : 0)
                }
                .frame(width: 26, height: 26)
                .animation(.interactiveSpring, value: deviceSelected)
            }
            .fontDesign(.rounded)
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(deviceSelected ? Color.accentColor.opacity(0.15) : Color.primary.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(deviceSelected ? Color.accentColor.opacity(0.55) : Color.primary.opacity(0.08), lineWidth: 1)
                    }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal)
    }

    /// Device starts selected and stays that way until a group is played, which
    /// is what gets remembered — the same stored choice the share extension
    /// reads, so the two screens agree on where "last time" was.
    private func restoreDestination() {
        guard case let .group(id) = PlayDestination.remembered else { return }
        guard let group = sonosService.groups.first(where: { $0.coordinatorID == id }) else { return }
        playOnThisDevice = false
        selections = Set(group.rooms.map(\Room.id))
        if groupVolume.isZero {
            groupVolume = group.groupVolume
        }
    }

    private func playHere() {
        guard let content else { return }
        Task {
            HapticManager.shared.fireHaptic(.buttonPress)
            do {
                try await LocalPlaybackService.shared.enqueue(content, at: selectedPosition)
                PlayDestination.device.remember()
                // Same reason as the route button: a group left in here would
                // outrank the device on the next play.
                selectedGroupService.group = nil
                AlertService.shared.showAlertContent(
                    with: content,
                    subtitle: "Playing on this device",
                    symbolName: "iphone.radiowaves.left.and.right"
                )
                dismiss()
            } catch {
                AlertService.shared.showAlert(with: error.localizedDescription, imageName: "exclamationmark.triangle")
            }
        }
    }

    func play(group: GroupRoom) {
        HapticManager.shared.fireHaptic(.buttonPress)
        PlayDestination.group(group.coordinatorID).remember()
        withAnimation {
            dismiss()
        } completion: {
            Task {
                selectedGroupService.group = group
                try await onSelection?(group)
            }
        }
    }
}

#Preview {
    @Previewable @State var group: GroupRoom? = nil
    Text(group?.nameWithCount ?? "Select")
        .sheet(isPresented: .constant(true)) {
            SelectGroupView(content: PlayableContent(
                title: "Cold Heart - PNAU Remix",
                subtitle: "Elton John, Dua Lipa, PNAU",
                thumbnail: URL(
                    string: "https://i.scdn.co/image/ab67616d00004851523458c391fe8180a19a1069"
                ),
                artwork: URL(
                    string: "https://i.scdn.co/image/ab67616d0000b273523458c391fe8180a19a1069"
                ),
                content: MediaContent(service: MusicService.spotify, id: "7rglLriMNBPAyuJOMGwi39", type: .track, location: URL(string:"https://open.spotify.com/track/7rglLriMNBPAyuJOMGwi39"))
            ))
            .environment(SelectedGroupService())
            .withEnvironments()
            .presentationBackground(.ultraThickMaterial)
            .presentationDetents([.fraction(0.7), .large])
        }
}


