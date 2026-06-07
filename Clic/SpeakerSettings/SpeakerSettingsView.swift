import SwiftUI
import SonosKit

struct SpeakerSettingsView: View {
    @Environment(\.dismiss) var dismiss
    @Environment(SonosService.self) var sonosService
    @Environment(\.liveActivityManager) var liveActivityManager
    
    @State var room: Room
    
    var body: some View {
        Form {
#if os(iOS) && !targetEnvironment(macCatalyst)
            Section("Live Activity") {
                Toggle(isOn: Binding(
                    get: { !liveActivityManager.isActivityDisabled(id: room.id) },
                    set: { enabled in
                        Task {
                            if enabled {
                                liveActivityManager.enableActivity(id: room.id)
                            } else {
                                liveActivityManager.disableActivity(id: room.id)
                            }
                        }
                    }
                )) {
                    VStack(alignment: .leading) {
                        Text("Lock Screen Controls")
                        Text("Show playback controls on lock screen")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .tint(.accentColor)
            }
#endif
            
            Section {
                VStack {
                    LabeledContent {
                        Text(room.settings.bass, format: .number)
                    } label: {
                        Text("Bass")
                    }
                    
                    Slider(value: $room.settings.bass, in: -10...10, step: 1) {
                        Text("Bass")
                    } minimumValueLabel: {
                        Text("-10")
                            .foregroundStyle(.secondary)
                    } maximumValueLabel: {
                        Text("10")
                            .foregroundStyle(.secondary)
                    } onEditingChanged: { isChanging in
                        Task {
                            await sonosService.setBass(room: room)
                        }
                    }
#if !os(visionOS)
                    .sensoryFeedback(.impact, trigger: room.settings.bass)
#endif
                }
                
                VStack {
                    LabeledContent {
                        Text(room.settings.treble, format: .number)
                    } label: {
                        Text("Treble")
                    }
                    
                    Slider(value: $room.settings.treble, in: -10...10, step: 1) {
                        Text("Bass")
                    } minimumValueLabel: {
                        Text("-10")
                            .foregroundStyle(.secondary)
                        
                    } maximumValueLabel: {
                        Text("10")
                            .foregroundStyle(.secondary)
                    } onEditingChanged: { isChanging in
                        Task {
                            await sonosService.setTreble(room: room)
                        }
                    }
#if !os(visionOS)
                    .sensoryFeedback(.impact, trigger: room.settings.treble)
#endif
                }
                
                Toggle(isOn: $room.settings.loudness) {
                    Text("Loudness")
                }.onChange(of: room.settings.loudness) { oldValue, newValue in
                    if oldValue != newValue {
                        Task {
                            await sonosService.setLoudness(room: room)
                        }
                    }
                }
                
                LabeledContent {
                    if room.settings.truePlay {
                        Text("Enabled")
                    } else {
                        Link(destination: URL(string: "sonos://")!) {
                            Text("Setup in Sonos App…")
                        }
                    }
                } label: {
                    Text("Trueplay")
                }
                
                //                LabeledContent("EQ") {
                Button {
                    HapticManager.shared.fireHaptic(.buttonPress)
                    Task {
                        await sonosService.resetEQ(room: room)
                        room.settings = await sonosService.getSpeakerSettings(room: room)
                    }
                } label: {
                    Text("Restore to Default")
                }
                .tint(.red)
                //                }
            }
            
            if room.isSoundbar {
                Section {
                    Text(room.theaterSettings.audioInputFormat.description)
                    
                    Toggle(isOn: $room.theaterSettings.nightMode) {
                        Text("Night Mode")
                    }
                    .onChange(of: room.theaterSettings.nightMode) { oldValue, newValue in
                        if oldValue != newValue {
                            Task {
                                try? await sonosService.setNightMode(room.ip, enabled: newValue)
                            }
                        }
                    }
                    
                    if room.isArcUltra {
                        Toggle(isOn: Binding(
                            get: { room.theaterSettings.speechEnhanceEnabled ?? false },
                            set: { room.theaterSettings.speechEnhanceEnabled = $0 }
                        )) {
                            Text("Speech Enhancement")
                        }
                        .onChange(of: room.theaterSettings.speechEnhanceEnabled) { oldValue, newValue in
                            guard let newValue, oldValue != newValue else { return }
                            Task {
                                try? await sonosService.setSpeechEnhanceEnabled(room.ip, enabled: newValue)
                            }
                        }

                        if room.theaterSettings.speechEnhanceEnabled == true {
                            Picker("Dialog Level", selection: $room.theaterSettings.dialogLevelValue) {
                                Text("Low").tag(1)
                                Text("Medium").tag(2)
                                Text("High").tag(3)
                                Text("Max").tag(4)
                            }
                            .onChange(of: room.theaterSettings.dialogLevelValue) { oldValue, newValue in
                                if oldValue != newValue {
                                    Task {
                                        try? await sonosService.setDialogLevelValue(room.ip, value: newValue)
                                    }
                                }
                            }
                        }
                    } else {
                        Toggle(isOn: $room.theaterSettings.dialogLevel) {
                            Text("Speech Enhancement")
                        }
                        .onChange(of: room.theaterSettings.dialogLevel) { oldValue, newValue in
                            if oldValue != newValue {
                                Task {
                                    try? await sonosService.setDialogLevel(room.ip, enabled: newValue)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Home Theater")
                }
                .listSectionSpacing(12)
                
                Section {
                    Toggle(isOn: $room.theaterSettings.isSurroundEnable) {
                        Text("Surround Enabled")
                    }.onChange(of: room.theaterSettings.isSurroundEnable) { oldValue, newValue in
                        if oldValue != newValue {
                            Task {
                                await sonosService.setEQ(room: room, eq: .surroundEnable, value: NSNumber(booleanLiteral: room.theaterSettings.isSurroundEnable).intValue)
                            }
                        }
                    }
                    
                    VStack {
                        LabeledContent {
                            Text("\(Int(room.theaterSettings.surroundLevel.rounded()))")
                                .foregroundStyle(.primary)
                                .bold()
                                .monospacedDigit()
                        } label: {
                            Text("TV Level")
                        }
                        
                        Slider(value: $room.theaterSettings.surroundLevel, in: EQType.surroundLevel.range, step: 1) {
                            Text("TV Level")
                        } minimumValueLabel: {
                            Text(EQType.surroundLevel.range.lowerBound, format: .number)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text(EQType.surroundLevel.range.upperBound, format: .number)
                                .foregroundStyle(.secondary)
                        } onEditingChanged: { isChanging in
                            Task {
                                await sonosService.setEQ(room: room, eq: .surroundLevel, value: Int(room.theaterSettings.surroundLevel))
                            }
                        }
#if !os(visionOS)
                        .sensoryFeedback(.impact, trigger: room.theaterSettings.surroundLevel)
#endif
                    }
                    
                    VStack {
                        LabeledContent {
                            Text("\(Int(room.theaterSettings.musicSurroundLevel.rounded()))")
                                .foregroundStyle(.primary)
                                .bold()
                                .monospacedDigit()
                        } label: {
                            Text("Music Level")
                        }
                        
                        Slider(value: $room.theaterSettings.musicSurroundLevel, in: EQType.musicSurroundLevel.range, step: 1) {
                            Text("Music Level")
                        } minimumValueLabel: {
                            Text(EQType.musicSurroundLevel.range.lowerBound, format: .number)
                                .foregroundStyle(.secondary)
                        } maximumValueLabel: {
                            Text(EQType.musicSurroundLevel.range.upperBound, format: .number)
                                .foregroundStyle(.secondary)
                        } onEditingChanged: { isChanging in
                            Task {
                                await sonosService.setEQ(room: room, eq: .musicSurroundLevel, value: Int(room.theaterSettings.musicSurroundLevel))
                            }
                        }
#if !os(visionOS)
                        .sensoryFeedback(.impact, trigger: room.theaterSettings.musicSurroundLevel)
#endif
                    }
                    VStack(alignment: .leading) {
                        Text("Music Playback")
                        Picker(selection: $room.theaterSettings.surroundMode) {
                            Text("Ambient")
                                .tag(0.0)
                            Text("Full")
                                .tag(1.0)
                        } label: {
                            Text("Music Playback")
                        }
                        .pickerStyle(.segmented)
                        .onChange(of: room.theaterSettings.surroundMode) { oldValue, newValue in
                            if oldValue != newValue {
                                Task {
                                    await sonosService.setEQ(room: room, eq: .surroundMode, value: Int(room.theaterSettings.surroundMode))
                                }
                            }
                        }
                    }
                }
                .listSectionSpacing(12)
                
                Section {
                    VStack {
                        LabeledContent {
                            Text(room.theaterSettings.heightChannel, format: .number)
                                .foregroundStyle(.primary)
                                .bold()
                                .monospacedDigit()
                        } label: {
                            Text("Height Level")
                        }
                        
                        Slider(value: $room.theaterSettings.heightChannel, in: EQType.heightChannelLevel.range, step: 1) {
                            Text("Height Level")
                        } minimumValueLabel: {
                            Text(EQType.heightChannelLevel.range.lowerBound, format: .number)
                                .foregroundStyle(.secondary)
                            
                        } maximumValueLabel: {
                            Text(EQType.heightChannelLevel.range.upperBound, format: .number)
                                .foregroundStyle(.secondary)
                        } onEditingChanged: { isChanging in
                            Task {
                                await sonosService.setEQ(room: room, eq: .heightChannelLevel, value: Int(room.theaterSettings.heightChannel))
                            }
                        }
#if !os(visionOS)
                        .sensoryFeedback(.impact, trigger: room.theaterSettings.heightChannel)
#endif
                    }
                } footer: {
                    Text("This setting is used when playing spatial audio with height channels, like Dolby Atmos. It adjusts the volume of the height channels to account for ceiling height. For high ceilings, a higher setting (+10) is recommended. Many users prefer +5 to +10 for a more noticeable height effect, regardless of ceiling height.")
                }
                .listSectionSpacing(12)
            }
            
            if room.subs.count > 0 {
                Section {
                    Toggle(isOn: $room.theaterSettings.isSubEnabled) {
                        Text("Sub")
                    }.onChange(of: room.theaterSettings.isSubEnabled) { oldValue, newValue in
                        if oldValue != newValue {
                            Task {
                                await sonosService.setEQ(room: room, eq: .subEnable, value: NSNumber(booleanLiteral: room.theaterSettings.isSubEnabled).intValue)
                            }
                        }
                    }
                    VStack {
                        LabeledContent {
                            Text("\(Int(room.theaterSettings.subGain.rounded()))")
                        } label: {
                            Text("Sub Level")
                        }
                        
                        Slider(value: $room.theaterSettings.subGain, in: EQType.subGain.range, step: 1) {
                            Text("Sub Level")
                        } minimumValueLabel: {
                            Text(EQType.subGain.range.lowerBound, format: .number)
                                .foregroundStyle(.secondary)
                            
                        } maximumValueLabel: {
                            Text(EQType.subGain.range.upperBound, format: .number)
                                .foregroundStyle(.secondary)
                        } onEditingChanged: { isChanging in
                            Task {
                                await sonosService.setEQ(room: room, eq: .subGain, value: Int(room.theaterSettings.subGain))
                            }
                        }
#if !os(visionOS)
                        .sensoryFeedback(.impact, trigger: room.theaterSettings.heightChannel)
#endif
                    }
                }
            }
            
            Section {
                HStack {
                    Text(room.ip)
                        .textSelection(.enabled)
                    Spacer()
                    if room.ethernetEnabled {
                        Image(systemName: "wifi.router.fill")
                    }
                }
                
                // MARK: Add Back
                if let channelMap = room.channelMap {
                    Text(channelMap)
                }
                
                if let channelMap = room.satChannelMap {
                    Text(channelMap)
                }
                if let info = room.info {
                    Text(info.modelDisplayName)
                }
                
                if let battery = room.battery {
                    HStack {
                        Text("Battery")
                        Spacer()
                        Text((battery.percentage / 100), format: .percent)
                            .foregroundStyle(.secondary)
                        if battery.chargingState == .charging {
                            Image(systemName: "battery.100percent.bolt")
                                .symbolRenderingMode(.hierarchical)
                                .foregroundStyle(battery.percentage > 90.0 ? Color.green.gradient : Color.orange.gradient)
                        }
                    }
                }
            } header: {
                Text("Hardware")
            }
        }
        .toolbarBackground(.thinMaterial, for: .navigationBar)
        .tint(.accentColor)
        .scrollContentBackground(.hidden)
        .toolbarTitleDisplayMode(.inline)
        .navigationTitle(room.name)
        .task {
            room.info = await sonosService.info(room: room)
            room.settings = await sonosService.getSpeakerSettings(room: room)
            room.theaterSettings = await sonosService.getTheaterSettings(room: room)
        }
        .headerProminence(.increased)
        .fontDesign(.rounded)
        .addDismiss(action: dismiss.callAsFunction)
    }
}

#Preview {
    NavigationStack {
        SpeakerSettingsView(room: .gym)
            .environment(SonosService.shared)
    }
}

#Preview("Theater") {
    Text("Theater")
        .sheet(isPresented: .constant(true)) {
            NavigationStack {
                SpeakerSettingsView(room: .theater)
                    .environment(SonosService.shared)
                    .presentationDetents([.large])
            }
        }
}

#Preview("Living Room") {
    NavigationStack {
        SpeakerSettingsView(room: .livingRoom)
            .environment(SonosService.shared)
    }
}
