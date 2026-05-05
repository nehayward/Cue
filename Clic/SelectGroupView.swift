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
    @State private var filter: String = ""
    @State private var groupVolume: Double = 0
    @State private var selections = Set<String>()
    
    var onSelection: ((GroupRoom) async throws -> Void)? = nil
    
    private var activeRooms: [Room] {
        sonosService.sortedRooms.filter { $0.state == .active }
    }
    
    private var allSelected: Bool {
        !activeRooms.isEmpty && selections.count == activeRooms.count
    }
    
    private var playingRooms: [Room] {
        activeRooms.filter { $0.isPlaying }
    }
    
    private var otherRooms: [Room] {
        activeRooms.filter { !$0.isPlaying }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let content {
                    PlayableContentView(item: content, hideDetails: true)
                        .padding()
                        .glass26()
                        .padding([.vertical, .horizontal])
                }
                
                ScrollView {
                    LazyVStack {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(sonosService.groups.filter { $0.rooms.count > 1 } ) { group in
                                    Button {
                                        play(group: group)
                                    } label: {
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
                                            RoundedRectangle(cornerRadius: 12)
                                                .foregroundStyle(.thinMaterial)
                                        }
                                        .containerRelativeFrame(.horizontal, alignment: .topLeading) { length, axis in
                                            length / 1.75
                                        }
                                    }
                                }
                            }
                            .padding(.horizontal)
                        }
                        .scrollIndicators(.hidden)
                        .scrollClipDisabled()
                        Divider()
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
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
                            Text(allSelected ? "Deselect All" : "Everywhere")
                                .contentTransition(.identity)
                                .frame(maxWidth: .infinity)
                                .bold()
                        }
                        .buttonStyle(.bordered)
                        .fontDesign(.rounded)
                        .tint(.accent)
                        .foregroundStyle(.accent)
                        .padding(.horizontal)
                        
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
                .contentMargins(.bottom, EdgeInsets(top: 0, leading: 0, bottom: 120, trailing: 0), for: .scrollContent)
                .overlay(alignment: .bottom) {
                    VStack {
                        HStack {
                            Button {
                                groupVolume = max(0, groupVolume - 2)
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
                                groupVolume = min(100, groupVolume + 2)
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
                                        for room in selectedRooms {
                                            await sonosService.setDeviceVolume(ip: room.ip, volume: Int(groupVolume))
                                            await sonosService.setRoomMute(IP: room.ip, mute: false)
                                        }
                                        try await onSelection?(newGroup)
                                        try await Task.sleep(for: .seconds(1))
                                        await sonosService.snapShotGroup(ip: newGroup.ip)
                                        print("DONE!")
                                    }
                                }
                            }
                        } label: {
                            Text("Play")
                                .bold()
                                .frame(maxWidth: .infinity)
                        }
                        .transition(.slide)
                        .buttonStyle(.borderedProminent)
                        .disabled(selections.isEmpty)
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
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load(useCache: true)
            }
        }
        .addDismiss {
            dismiss()
        }
        .animation(.default, value: sonosService.sorted)
        .animation(.default, value: selections)
        .animation(.default, value: playingRooms.map(\.id))
        .animation(.default, value: activeRooms.map { "\($0.id)-\($0.isPlaying)-\($0.track.name)" })
    }
    
    @ViewBuilder
    private func roomRow(room: Room) -> some View {
        Menu {
            if !room.track.name.isEmpty {
                Section {
                    Label(room.track.name, systemImage: "music.note")
                    if !room.track.artist.isEmpty {
                        Label(room.track.artist, systemImage: "person.fill")
                    }
                }
            }
            
            Section {
                Button {
                    HapticManager.shared.fireHaptic(.selection)
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
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(room.name)
                        .fontWeight(.semibold)
                    
                    if !room.track.name.isEmpty {
                        Text(room.track.name)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(room.isPlaying ? .accent : .secondary)
                    }
                }
                
                Spacer()
                
                Text("\(Int(room.volume))")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                
                Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .symbolRenderingMode(.hierarchical)
                    .contentTransition(.symbolEffect(.replace))
                    .foregroundStyle(selections.contains(room.id) ? Color.accentColor : .primary.opacity(0.7))
            }
            .fontDesign(.rounded)
            .padding(.horizontal)
            .padding(.vertical, 12)
        } primaryAction: {
            HapticManager.shared.fireHaptic(.selection)
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
    
    func play(group: GroupRoom) {
        HapticManager.shared.fireHaptic(.buttonPress)
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


