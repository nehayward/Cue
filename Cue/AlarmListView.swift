import SwiftUI
import SonosKit
import VibesDS

struct AlarmListView: View {
    @Environment(Router.self) var router: Router?
    @Environment(SonosService.self) var sonosService
    @State var group: GroupRoom? = nil
    @State var alarms: [Alarm] = []
    @State var isLoaded: Bool = false

    /// Groups the household's alarms for display.
    ///
    /// `listAlarms()` returns alarms for the *entire* household, but a speaker
    /// may not be present in `sortedRooms` right now — it can be powered off,
    /// not yet discovered, or invisible (a stereo-pair secondary, bonded
    /// surround, or sub). Previously we iterated `sortedRooms` and matched
    /// `roomID == room.id`, so any alarm whose room wasn't currently visible
    /// was silently dropped. Here we group by the alarms themselves: known
    /// rooms keep their named sections (in sorted-room order), and anything
    /// left over is collected into a single trailing section so it is never
    /// hidden.
    private var alarmSections: [(id: String, name: String, alarms: [Alarm])] {
        let byRoom = Dictionary(grouping: alarms, by: { $0.roomID })
        var sections: [(id: String, name: String, alarms: [Alarm])] = []
        var matchedRoomIDs: Set<String> = []

        for room in sonosService.sortedRooms {
            guard let roomAlarms = byRoom[room.id], !roomAlarms.isEmpty else { continue }
            sections.append((id: room.id, name: room.name, alarms: roomAlarms))
            matchedRoomIDs.insert(room.id)
        }

        let orphanAlarms = alarms.filter { !matchedRoomIDs.contains($0.roomID) }
        if !orphanAlarms.isEmpty {
            sections.append((id: "__other__", name: "Other Speakers", alarms: orphanAlarms))
        }

        return sections
    }

    var body: some View {
        List {
            ForEach(alarmSections, id: \.id) { section in
                let roomAlarms = section.alarms
                if !roomAlarms.isEmpty {
                    Section(section.name) {
                        ForEach(roomAlarms) { alarm in
                            let enabledBinding = Binding<Bool>(
                                get: { alarms.first(where: { $0.id == alarm.id })?.enabled ?? alarm.enabled },
                                set: { newValue in
                                    guard let i = alarms.firstIndex(where: { $0.id == alarm.id }) else { return }
                                    alarms[i].enabled = newValue
                                }
                            )
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
                                        Toggle("Enabled", isOn: enabledBinding)
                                            .labelsHidden()
                                            .onChange(of: enabledBinding.wrappedValue) {
                                                guard let updated = alarms.first(where: { $0.id == alarm.id }) else { return }
                                                Task {
                                                    await sonosService.editAlarm(alarm: updated, content: nil)
                                                }
                                            }
                                    }
                                    HStack {
                                        VibeSlider(value: .constant(alarm.volume))
                                            .foregroundStyle(.accent)
                                            .disabled(true)
                                            .accessibilityHidden(true)
                                        Text(alarm.volume, format: .number) + Text("%")
                                    }
                                }
                                .fontDesign(.rounded)
                                .swipeActions {
                                    Button(role: .destructive) {
                                        let alarmToDelete = alarm
                                        alarms.removeAll { $0.id == alarmToDelete.id }
                                        Task {
                                            await sonosService.deleteAlarm(alarm: alarmToDelete)
                                        }
                                    } label: {
                                        Label("Delete", systemImage: "trash.fill")
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
        .refreshable {
            if let fetched = await sonosService.listAlarms() {
                alarms = fetched
            }
            isLoaded = true
        }
        .onAppear {
            isLoaded = false
            Task {
                try? await Task.sleep(for: .milliseconds(300))
                var fetched = await sonosService.listAlarms()
                // Retry only when the request itself failed (nil) — e.g. a
                // speaker that's still being discovered. A successful response
                // with no alarms ([]) is authoritative, so we don't keep hitting
                // the network or stall the empty state for genuinely-empty
                // households.
                var attempt = 0
                while fetched == nil, attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(500))
                    fetched = await sonosService.listAlarms()
                    attempt += 1
                }
                alarms = fetched ?? []
                isLoaded = true
            }
        }
        .navigationTitle("Alarms")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                NavigationLink(value: RouterDestination.addAlarm(group: group)) {
                    Label("Add", systemImage: "plus")
                        .labelStyle(.iconOnly)
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
