import SwiftUI
import WatchKit
import SonosKitMini

struct GroupScreen: View {
    @Environment(SonosMiniService.self) var sonosService: SonosMiniService
    @Environment(\.dismiss) var dismiss

    @State private var id: String
    @State private var selections: Set<String> = []

    init(id: String) {
        self.id = id
    }
    
    var body: some View {
        Group {
            if let deviceIndex = sonosService.devices.firstIndex(where: { $0.id == id }) {
                deviceView(for: deviceIndex)
            } else {
                Text("Vanished")
            }
        }.task {
            print("Load")
            if sonosService.devices.isEmpty {
                try? await sonosService.updateDevices(useCache: true)
            }
            
            guard let foundGroup = sonosService.devices.first(where: { $0.id == id }) else {
                return
            }
            
            print(foundGroup.name)
            selections = Set(foundGroup.allDevices.map { $0.id })
            print(selections)
            print(foundGroup.allDevices.map(\.name))
            print(foundGroup.rooms.map(\.name))
        }
    }
    
    @ViewBuilder
    func deviceView(for index: Int) -> some View {
        let device = sonosService.devices[index]
        List {
            ForEach(sonosService.sorted) { device in
                Button {
                    WKInterfaceDevice.current().play(.click)
                    addGroup(device.id)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            HStack {
                                VStack {
                                    Text(device.name)
                                        .font(.title3)
                                        .bold()
                                }
                                Spacer()
                            }
                        }
                        Spacer()
                        Image(systemName: selections.contains(device.id) ? "checkmark.circle.fill" : "circle")
                            .symbolEffect(.bounce, options: .speed(3), value: selections.contains(device.id))
                            .font(.title3)
                            .bold()
                            .opacity(isSelected(device) ? 1 : 0.8)
                    }
                    .fontDesign(.rounded)
                }
                .listRowBackground(selections.contains(device.id) ? RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.fill)
                : nil)
            }
        }
        .navigationTitle("\(device.nameWithCount)")
    }
    
//    private func addGroup(id: String) {
//        if selections.contains(id), selections.count == 1 { return }
//        let oldRooms = sonosService.devices.filter { room in selections.contains(room.id) }
//
//        selections.formSymmetricDifference([id])
//        let devices = sonosService.devices.filter { selections.contains($0.id) }
//
//        Task {
//            print(devices.map(\.name))
////            guard let group = sonosService.devices.first(where: { $0.id == id }) else { return }
//            guard let newCoordinatorID = await sonosService.speedGroup(devices: devices) else { return }
//            if !selections.contains(id) {
//                // MARK: Reassign coordinatorID
//                self.id = newCoordinatorID.id
//                Task { @MainActor in
//                    if Router.main.path.isEmpty { return }
//                    Router.main.selectedID = id
//                }
//            }
//            
//            try? await sonosService.updateWatchDevices(from: oldRooms)
//        }
//
//        
//    }
//
    
    
    private func addGroup(_ addingID: String) {
        if selections.contains(addingID), selections.count == 1 { return }
        let oldRooms = sonosService.devices.filter { room in selections.contains(room.id) }
        
        selections.formSymmetricDifference([addingID])
        let devices = sonosService.devices.filter { selections.contains($0.id) }
        
        
        Task {
            print(devices.map(\.name))
            guard let device = sonosService.devices.first(where: { $0.id == id }) else { return }
            guard let newCoordinatorID = await sonosService.smartGroup(rooms: devices, oldRooms: oldRooms, to: device) else { return }

            if !selections.contains(id) {
                withAnimation {
                    self.id = newCoordinatorID
                    Router.main.selectedID = id
                }
            }
            try? await sonosService.updateWatchDevices(from: oldRooms)
        }
    }
    
    func isSelected(_ device: SonosDevice) -> Bool {
        selections.contains(device.id)
    }
}

#Preview {
    Text("Grouping")
        .sheet(isPresented: .constant(true)) {
            GroupScreen(id: "RINCON_7828CAC7352E01400")
                .environment(SonosMiniService.shared)
        }
}
