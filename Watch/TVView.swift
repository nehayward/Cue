import SwiftUI
import SonosKit

struct TVView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @Environment(Popover.self) var popOver: Popover

    @Binding var group: GroupRoom
    @State private var volumeTask: Task<Void, Error>?
    @State private var isIdle: Bool = true

    var body: some View {
        VStack(alignment: .center) {
            VStack {
                if let settings = group.tvSettings {
                    Text(settings.audioInputFormat.description)
                        .bold()
                }
                Text("\(Text(group.groupVolume, format: .number))%")
                Spacer()
                HStack {
                    if let settings = Binding<TVSettings>($group.tvSettings) {
                        Toggle("Night Mode", systemImage: "moon.zzz.fill", isOn: settings.nightMode)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .onChange(of: settings.nightMode.wrappedValue) { oldValue, newValue in
                                Task {
                                    try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: newValue)
                                    group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                                }
                            }

                        Toggle("Dialog Mode", systemImage: "person.wave.2.fill", isOn: settings.dialogLevel)
                            .symbolRenderingMode(.hierarchical)
                            .labelStyle(.iconOnly)
                            .toggleStyle(.button)
                            .onChange(of: settings.dialogLevel.wrappedValue) { oldValue, newValue in
                                Task {
                                    try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled: newValue)
                                    group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                                }
                            }
                    }
                }
            }
            .fontDesign(.rounded)
        }
        .padding()
        .onAppear {
            if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                sonosService.monitor()
            }
        }
        .tag(group.coordinatorID)
        .focusable()
        .digitalCrownRotation(detent: $group.groupVolume,
                              from: 0,
                              through: 100,
                              by: 2,
                              sensitivity: .low,
                              isContinuous: false,
                              isHapticFeedbackEnabled: true,
                              onChange: { crownEvent in
            isIdle = false
            withAnimation {
                popOver.isShowing = !isIdle
            }
            popOver.text = String(format: "%.0f", group.groupVolume)
        }, onIdle: {
            isIdle = true
            withAnimation {
                popOver.isShowing = !isIdle
            }
        })
        .onChange(of: group.groupVolume) {
            if isIdle { return }
            volumeTask?.cancel()
            volumeTask = Task {
                await sonosService.setGroupVolume(ip: group.coordinatorRoom.ip, volume: Int(group.groupVolume))
            }
        }
        .navigationTitle(group.coordinatorRoom.name + "\(group.rooms.count > 1 ? " + \(group.rooms.count - 1)" : "")")
    }
}

#Preview {
    NavigationStack {
        TVView(group: .constant(.theater))
            .environment(SonosService())
            .environment(Popover())
    }
    .listStyle(.carousel)
}

