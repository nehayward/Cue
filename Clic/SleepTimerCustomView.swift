import SwiftUI
import Defaults
import SonosKit

struct SleepTimerCustomView: View {
    @Environment(SonosService.self) var sonosService
    @Environment(\.dismiss) var dismiss

    var recentTimers: Storage<Duration>
    var group: GroupRoom

    @State private var hours: Int = 0
    @State private var minutes: Int = 1

    var body: some View {
        NavigationStack {
            VStack {
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
                        let duration = Duration.seconds((hours * 60 * 60) + minutes * 60)
                        recentTimers.object.insert(duration, at: 0)
                        await sonosService.sleepTimer(group: group, duration: duration)
                        dismiss()
                    }
                } label: {
                    Text("Start")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .padding()
            }
            .addDismiss(action: dismiss.callAsFunction)
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(24)
        }
    }
}

#Preview {
    Text("HERE")
        .sheet(isPresented: .constant(true)) {
//            SleepTimerCustomView(group: .gym)
        }
}
