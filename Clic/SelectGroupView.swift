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

    @State var content: PlayableContent?
    @State private var filter: String = ""
    @State private var groupVolume: Double = 0
    @State private var selections = Set<String>()
    @State private var rooms: [Room] = []
    @State private var search: Bool = false

    var onSelection: ((GroupRoom) async throws -> Void)? = nil

    var body: some View {
        NavigationStack {
            List {
//                if onSelection != nil {
//                    Text("Select Group To Play")
//                        .bold()
//                        .font(.title)
//                        .multilineTextAlignment(.center)
//                        .listRowBackground(Color.clear)
//                        .frame(maxWidth: .infinity, alignment: .center)
//                }
                if let content {
                    PlayableContentView(item: content, hideDetails: true)
                        .listRowBackground(Color.clear)
                        .padding(.leading, -20)

//                    HStack {
//                        ContentArtworkView(content: content)
//                            .frame(width: 50, height: 50)
//                            .background(.red)
//                        VStack {
//                            Text(content.title)
//                            Text(content.subtitle)
//                                .foregroundStyle(.secondary)
//                        }
//                    }
//                    .listRowBackground(Capsule().foregroundStyle(.thickMaterial))
                }
                Button {
                    HapticManager.shared.fireHaptic(.selection)
                    for room in rooms {
                        if groupVolume.isZero {
                            groupVolume = room.volume
                        }
                        selections.insert(room.id)
                    }
                } label: {
                    Text("Everywhere")
                        .frame(maxWidth: .infinity)
                        .bold()
                }
                .buttonStyle(.bordered)
                .fontDesign(.rounded)
                .tint(.accent)
                .foregroundStyle(.accent)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
                
                ForEach($rooms) { $room in
                    VStack {
                        Button {
                            HapticManager.shared.fireHaptic(.selection)
                            if selections.contains(room.id) {
                                selections.remove(room.id)
                            } else {
                                selections.insert(room.id)
                                if groupVolume.isZero {
                                    groupVolume = room.volume
                                }
                            }
                        } label: {
                            HStack {
                                Text(room.name)
                                    .bold()
                                Spacer()
                                Image(systemName: selections.contains(room.id) ? "checkmark.circle.fill" : "circle")
                                    .symbolRenderingMode(.hierarchical)
//                                    .symbolEffect(.automatic, options: .speed(5), value: selections.contains(room.id))
                                    .foregroundStyle(selections.contains(room.id) ? Color.accentColor : .primary.opacity(0.7))
                            }
                            .fontDesign(.rounded)
                 
                        }
                        //                        RoomVolumeView(room: $room, touchDelay: 0.05)
                        //                            .foregroundStyle(selections.contains(room.id) ? .black : .primary)
                        //                            .tint(selections.contains(room.id) ? .black : .accentColor)
                    }
                    //                    .listRowBackground(
                    //                        selections.contains(room.id) ? RoundedRectangle(cornerRadius: 12)
                    //                            .foregroundStyle(Color.accentColor.gradient.opacity(0.8))
                    //                        : nil
                    //                    )
                }
            }
//            .toolbar {
//                ToolbarItem(placement: .bottomBar) {
//                    VStack {
//                        VibeSlider(value: .constant(12), step: 1)
//                        Button {
//                            print("group")
//                        } label: {
//                            Text("Play")
//                                .frame(maxWidth: .infinity)
//                                .tint(.accent)
//                        }
//                        .transition(.slide)
//                        .buttonStyle(.bordered)
//                    }
//                    .padding()
//                }
//            }
//            .conditionalToolbarModifier(isSearching: search)
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
                    .frame(height: 24)
                    .padding(.bottom)
                    Button {
                        Task {
                            HapticManager.shared.fireHaptic(.buttonPress)
                            let rooms = rooms.filter { room in
                                selections.contains(room.id)
                            }
                            guard let newGroup = await sonosService.speedGroup(rooms: rooms) else {
                                print("Failed!")
                                return
                            }
                            withAnimation {
                                dismiss()
                            } completion: {
                                Task {
                                    selectedGroupService.group = newGroup
                                    for room in rooms {
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
                .background(.thinMaterial)
//                .clipShape(UnevenRoundedRectangle(cornerRadii: RectangleCornerRadii(topLeading: 12, bottomLeading: 0, bottomTrailing: 0, topTrailing: 12)))
            }
        }
        .scrollContentBackground(.hidden)
        .listRowSpacing(10)
        .foregroundStyle(.primary)
        .fontDesign(.rounded)
        .task {
            if sonosService.sortedRooms.isEmpty {
                try? await sonosService.load(useCache: true)
            }
            rooms = sonosService.sortedRooms.filter {
                $0.state == .active
            }.map {
                let room = Room(id: $0.id, ip: $0.ip, name: $0.name, channelMap: $0.channelMap)
                room.volume = $0.volume
                return room
            }
        }
        .addDismiss {
            dismiss()
        }
        .animation(.default, value: sonosService.sorted)
        .animation(.default, value: selections)
    }

    var filteredAndSortedGroups: [GroupRoom] {
        let filtered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) != nil }
        let nonFiltered = sonosService.sorted.filter { $0.nameWithCount.range(of: filter, options: .caseInsensitive) == nil }
        return (filtered + nonFiltered).sorted { $0.coordinatorRoom.isPlaying && !$1.coordinatorRoom.isPlaying }
    }
}

extension View {
    @ViewBuilder
    func conditionalToolbarModifier(isSearching: Bool) -> some View {
        if #available(iOS 18.0, *) {
//            self.toolbarVisibility(selections.isEmpty ? .hidden : .visible, for: .bottomBar)
            self.toolbarVisibility(isSearching ? .visible : .hidden, for: .navigationBar)
//            self.toolbarVisibility(.hidden, for: .navigationBar)
        } else {
            self // fallback behavior for earlier versions
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


