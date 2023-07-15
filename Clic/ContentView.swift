import SwiftUI
import SonosKit

enum ActiveSheet: Identifiable {
    case first, second

    var id: Int {
        hashValue
    }
}

struct ContentView: View {

    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popover: Popover

    @State var room: GroupRoom? = nil
    @State var selected: String? = nil
    @State var isEditing = false
    @State var grouping = false

    @State var multiSelection = Set<String>()
    @Namespace var namespace
    @State var activeSheet: ActiveSheet?

    @State var showGroup: Bool = false

    var body: some View {
        List {
            ForEach(sonosService.groups) { group in
                if selected != group.coordinatorID {
                    Section {
                        HStack {
                            ArtworkView(group: group)
                                .frame(width: 72, height: 72)
                            ZoneView(roomGroup: group)
                        }
                        .matchedGeometryEffect(id: group.id, in: namespace)
                        .onTapGesture {
                            activeSheet = .second
                            withAnimation {
                                selected = group.coordinatorID
                            }
                            room = group
                            
                        }
                    }.sheet(item: $activeSheet) { sheet in
                        switch sheet {
                        case .first, .second:
                            if selected != nil {
                                PlayerView(group: sonosService.groups.first(where: { group in
                                    group.coordinatorID == selected!
                                })!)
                //                    .matchedGeometryEffect(id: selected!.id, in: namespace)
                                .environment(sonosService)
                                .sheet(isPresented: $showGroup) {
                                    SceneBuilderScreen()
                                }
                            }
                        }
                    }
                }
            }
            
            SceneView(show: $showGroup)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
        }
        .safeAreaPadding(.bottom, 140)
//        .overlay(alignment: .bottom) {
//            if selected != nil{
//
////                HStack {
////                    Text(selected.rooms[0].name)
////                    Text(selected.rooms[0].track.name)
////                }
////                .frame(maxWidth: .infinity, maxHeight: 40)
////                .padding()
////                .background {
////                    RoundedRectangle(cornerRadius: 12)
////                        .foregroundStyle(.ultraThickMaterial)
////                }
////                .animation(.easeInOut(duration: 1), value: selected.id)
//
//                    HStack {
//                        ArtworkView(group: selected!)
//                        ZoneView(roomGroup: selected!)
//                    }
//                    .matchedGeometryEffect(id: selected!.id, in: namespace)
//
//
//            }
//        }
        .listSectionSpacing(10)
        .onAppear {
            sonosService.monitor()
        }
//        .overlay(alignment: .bottom) {
//            Rectangle()
//                .ignoresSafeArea()
//                .frame(height: 60)
//                .foregroundStyle(.thinMaterial)
//                .overlay {
//                    HStack {
//                        if grouping {
//                            Button("Cancel") {
//                                multiSelection.removeAll()
//                                grouping = false
//                            }
//                        }
//                        if grouping {
//                            Spacer()
//                        }
//                        Button {
//                            if multiSelection.count > 1 {
//                                if let firstRoom = multiSelection.popFirst() {
//
////                                    sonosService.group(rooms: multiSelection, to: firstRoom.coordinatorID)
//                                }
//                                grouping = false
//                            } else {
//                                grouping.toggle()
//                            }
//                        } label: {
//                            HStack {
//                                Image(systemName: "hifispeaker.2.fill")
//                                Text(!grouping ? "Group" : "Grouping \(multiSelection.count)")
//                                    .frame(minWidth: 100, alignment: .leading)
//                            }
//                        }
//                        .buttonStyle(.borderedProminent)
//                    }
//                    .animation(nil)
//                    .padding()
//                }
//                .animation(nil)
//
//        }
//        .toolbar {
//            ToolbarItemGroup(placement: .bottomBar) {
//                Button {
//                    isEditing.toggle()
//                } label: {
//                    HStack {
//                        Text(multiSelection.isEmpty ? "Group" : "Cancel")
//                        Image(systemName: "hifispeaker.2.fill")
//                    }
//                }
//                Spacer()
//                Button {
//                    isEditing = false
//                    print(multiSelection)
//                } label: {
//                    HStack {
//                        Text(!multiSelection.isEmpty ? "Group" : "")
//                    }
//                }
//            }
//            ToolbarItemGroup(placement: .secondaryAction) {
//                Button("Settings") {
//                    print("Credits tapped")
//                }
//
//                Button("Email Me") {
//                    print("Email tapped")
//                }
//            }
//
//        }
//        .environment(\.editMode, .constant(self.isEditing ? EditMode.active : EditMode.inactive))

    }
}

#Preview {
    NavigationStack {
        ContentView()
            .environment(SonosService())
    }
}

