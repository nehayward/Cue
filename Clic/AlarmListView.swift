import SwiftUI
import SonosKit
import VibesDS

struct AlarmListView: View {
    @Environment(Router.self) var router: Router?
    @Environment(SonosService.self) var sonosService
    @State var group: GroupRoom? = nil
    @State var alarms: [Alarm] = []
    @State var isLoaded: Bool = false

    var body: some View {
        List {
            ForEach(sonosService.sortedRooms) { room in
                if alarms.contains(where: { $0.roomID == room.id }) {
                    Section(room.name) {
                        ForEach($alarms) { $alarm in
                            if alarm.roomID == room.id {
                                NavigationLink(value: RouterDestination.editAlarm(alarm: alarm)) {
                                    VStack {
                                        HStack(alignment: .center) {
                                            VStack(alignment: .leading) {
                                                Text(alarm.startTime, format: .dateTime.hour().minute())
                                                    .bold()
                                                Text(alarm.schedule.sorted(by: { $0.order < $1.order }).map(\.shortTitle).joined(separator: ", "))
                                                if let content = sonosService.parseAlarmClockInfo(uri: alarm.programURI, metadataXML: alarm.programMetaData) {
                                                    Text(content.title)
                                                        .foregroundStyle(.secondary)
                                                }
                                            }
                                            Spacer()
                                            Toggle("Enabled", isOn: $alarm.enabled)
                                                .labelsHidden()
                                                .onChange(of: alarm.enabled) {
                                                    Task {
                                                        await sonosService.editAlarm(alarm: alarm, content: nil)
                                                    }
                                                }
                                        }
                                        HStack {
                                            VibeSlider(value: .constant(alarm.volume))
                                                .foregroundStyle(.accent)
                                                .disabled(true)
                                            Text(alarm.volume, format: .number) + Text("%")
                                        }
                                    }
                                    .fontDesign(.rounded)
                                    .swipeActions {
                                        Button(role: .destructive) {
                                            Task {
                                                await sonosService.deleteAlarm(alarm: alarm)
                                                alarms.removeAll { searchAlarm in
                                                    searchAlarm == alarm
                                                }
                                            }
                                        } label: {
                                            Label("Delete", systemImage: "trash.fill")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .headerProminence(.increased)
                }
            }
        }
        .listStyle(.insetGrouped)
        .onAppear {
            isLoaded = false
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                alarms = await sonosService.listAlarms()
                isLoaded = true
            }
        }
        .navigationTitle("Alarms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink(value: RouterDestination.addAlarm(group: group)) {
                    Image(systemName: "plus")
                }
            }
        }
        .environment(group)
        .overlay {
            if alarms.isEmpty, isLoaded {
                ContentUnavailableView {
                    Label("No Alarms", systemImage: "alarm.fill")
                } actions: {
                    NavigationLink("Add Alarm", value: RouterDestination.addAlarm(group: group))
                }
            } else if !isLoaded {
                ProgressView()
            }
        }
    }
}

//
//#Preview {
//    AlarmListView()
//}
