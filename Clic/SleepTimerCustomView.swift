import SwiftUI
import Defaults
import SonosKit

struct SleepTimerCustomView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(\.dismiss) var dismiss

//    @State private var recentTimers: Storage<Duration> = Storage("")
    var group: GroupRoom

    @State private var hours: Int = 0
    @State private var minutes: Int = 1

    var body: some View {
        NavigationStack {
            VStack {
                // TODO: Add later
                //            ForEach(recentTimers.object, id: \.self) { timer in
                //                VStack {
                //                    Text(timer.formatted(.time(pattern: .hourMinute)))
                //                }
                //            }
                HStack {
                    Picker("", selection: $hours){
                        ForEach(0..<23, id: \.self) { i in
                            Text("^[\(i) hours](inflect: true)")
                        }
                    }
                    Picker("", selection: $minutes){
                        ForEach(1..<60, id: \.self) { i in
                            Text("^[\(i) minutes](inflect: true)")
                        }
                    }
                }
                .pickerStyle(.wheel)

                Button {
                    Task {
                        //                    recentTimers.object.append(Duration.seconds((hours * 60 * 60) + minutes * 60))
                        await sonosService.sleepTimer(group: group, duration: Duration.seconds((hours * 60 * 60) + minutes * 60))
                        dismiss()
                    }
                } label: {
                    Text("Start")
                        .padding()
                }
                .buttonBorderShape(.circle)
                .buttonStyle(.borderedProminent)
            }
            .addDismiss(action: dismiss.callAsFunction)
        }
        .presentationDetents([.fraction(0.3)])
        .presentationBackground(.thinMaterial)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(24)
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
            SleepTimerCustomView(group: .gym)
        }
}
