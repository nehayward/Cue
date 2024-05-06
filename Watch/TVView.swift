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
                        Button {
                            Task {
                                try? await sonosService.setNightMode(group.coordinatorRoom.ip, enabled: !settings.nightMode.wrappedValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        } label: {
                            Label("Night Mode", systemImage: "moon.zzz.fill")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .toggleStyle(.button)
                                .foregroundStyle(settings.nightMode.wrappedValue ? .accent : .secondary.opacity(0.8))
                        }
                        .buttonStyle(.bordered)
                        .tint(settings.nightMode.wrappedValue ? .accent : nil)
                        .animation(.spring, value: settings.nightMode.wrappedValue)

                        Button {
                            Task {
                                try? await sonosService.setDialogLevel(group.coordinatorRoom.ip, enabled:  !settings.dialogLevel.wrappedValue)
                                group.tvSettings = try await sonosService.getTVSettings(ip: group.coordinatorRoom.ip)
                            }
                        } label: {
                            Label("Dialog Mode", systemImage: "person.wave.2.fill")
                                .symbolRenderingMode(.hierarchical)
                                .labelStyle(.iconOnly)
                                .toggleStyle(.button)
                        }
                        .buttonStyle(.bordered)
                        .foregroundStyle(settings.dialogLevel.wrappedValue ? .accent : .secondary.opacity(0.8))
                        .tint(settings.dialogLevel.wrappedValue ? .accent : nil)
                        .animation(.spring, value: settings.dialogLevel.wrappedValue)
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

