import SwiftUI
import SonosKit
import VibesDS

struct AlarmView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService

    var group: GroupRoom?
    var edit: Bool = false

    @State var alarm: Alarm
    @State private var editedAlarm: Alarm?
    @State private var hours: Int = 0
    @State private var minutes: Int = 0
    @State private var router: Router = Router()
    @State private var adding: ContentToAdd = ContentToAdd(add: true)

    var body: some View {
        Form {
            Picker("Room", selection: $alarm.roomID){
                ForEach(sonosService.sortedRooms) { room in
                    Text(room.name)
                        .tag(room.id)
                }
            }
            .pickerStyle(.menu)
            DatePicker("Time", selection: $alarm.startTime, displayedComponents: .hourAndMinute)
            HStack {
                Text("Duration")
                Picker("", selection: $hours){
                    ForEach(0..<23, id: \.self) { i in
                        Text("\(i) hours")
                            .tag(i)
                    }
                }
                .pickerStyle(.menu)
                Picker("", selection: $minutes){
                    ForEach(0..<60, id: \.self) { i in
                        Text("\(i) min").tag(i)
                    }
                }
                .pickerStyle(.menu)
            }
            HStack {
                Text("Schedule")
                Spacer()
                Menu {
                    ForEach(Schedule.allCases) { schedule in
                        Button {
                            if schedule == .once {
                                alarm.schedule.removeAll()
                            } else {
                                alarm.schedule.remove(.once)
                            }
                            if alarm.schedule.contains(schedule) {
                                alarm.schedule.remove(schedule)
                            } else {
                                alarm.schedule.insert(schedule)
                            }
                        } label: {
                            Text(schedule.title)
                            if alarm.schedule.contains(schedule) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                } label: {
                    Text(alarm.schedule.sorted(by: { $0.order < $1.order }).map(\.shortTitle).joined(separator: ", "))
                }
                .menuActionDismissBehavior(.disabled)
            }

            Toggle(isOn: $alarm.includeLinkedZones) {
                Text("Include Grouped Rooms")
            }

        // TODO: Add Options
//            Picker("Play Mode", selection: $alarm.playMode){
//                ForEach(PlayMode.allCases) { option in
//                    Text(String(describing: option))
//                }
//            }

            Section {
                Button {
                    router.presentedSheet = .searchAdd(adding: adding)
                } label: {
                    HStack {
                        Text("Music")
                        Spacer()
                        if let content = adding.content {
                            Text(content.title)
                                .lineLimit(1)
                        } else if let content = sonosService.parseAlarmClockInfo(uri: alarm.programURI, metadataXML: alarm.programMetaData) {
                            Text(content.title)
                                .foregroundStyle(.secondary)
                        }
                        if alarm.programURI != "x-rincon-buzzer:0" {
                            Button {
                                HapticManager.shared.fireHaptic(.buttonPress)
                                alarm.programURI = "x-rincon-buzzer:0"
                                alarm.programMetaData = nil
                                adding.content = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                        }
                    }
                }
                .tint(.primary)

                if alarm.programURI != "x-rincon-buzzer:0" {
                    Toggle(isOn: $alarm.shuffle) {
                        Text("Shuffle")
                    }
                }

                HStack {
                    VibeSlider(value: $alarm.volume)
                        .foregroundStyle(.accent)
                    Text(alarm.volume, format: .number)
                }
                .frame(height: 40)
            } footer: {
                Text("Only Albums and Playlist Supported.")
            }
        }
        .withSheetDestinations(sheetDestinations: $router.presentedSheet)
        .withFullScreenCoverDestinations(destinations: $router.presentedFullScreenCover)
        .fontDesign(.rounded)
        .navigationTitle("Save Alarm")
        .navigationBarTitleDisplayMode(.inline)
        .animation(.easeInOut, value: alarm.duration)
        .listSectionSpacing(12)
        .task {
            hours =  Int(alarm.duration.components.seconds % 86400) / 3600
            minutes =  Int(alarm.duration.components.seconds % 3600) / 60
            editedAlarm = alarm
            if let group {
                alarm.roomID = group.coordinatorRoom.id
                return
            }
            
            if !edit {
                alarm.roomID = sonosService.sorted.first?.coordinatorRoom.id ?? ""
                return
            }
            
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button {
                    if edit {
                        Task {
                            await sonosService.editAlarm(alarm: alarm, content: adding.content)
                        }
                    } else {
                        Task {
                            await sonosService.createAlarm(alarm: alarm, content: adding.content)
                        }
                    }
                    dismiss()
                } label: {
                    Label("Save", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(edit && editedAlarm == alarm && adding.content == nil)
            }
        }
        .onChange(of: minutes) {
            alarm.duration = .seconds(Int((hours * 3600) + (minutes * 60)))
        }
        .onChange(of: hours) {
            alarm.duration = .seconds(Int((hours * 3600) + (minutes * 60)))
        }
        .onChange(of: adding.content) {
            if let content = adding.content {
                alarm.programURI = content.uri
            }
        }
    }
}

//
//#Preview {
//    AlarmView(alarm: <#T##Alarm#>)
//}
