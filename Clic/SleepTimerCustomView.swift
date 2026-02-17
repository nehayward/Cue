import SwiftUI

struct SleepTimerCustomView: View {
    @Environment(\.dismiss) var dismiss
    
    var recentTimers: Storage<Duration>
    var onSelect: (Duration) async -> Void
    
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
                    let duration = Duration.seconds((hours * 60 * 60) + minutes * 60)
                    recentTimers.object.insert(duration, at: 0)
                    Task { await onSelect(duration) }
                    dismiss()
                } label: {
                    Text("Set")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.accentColor)
                .padding()
            }
            .addDismiss(action: dismiss.callAsFunction)
            .presentationDetents([.fraction(0.4)])
            .presentationDragIndicator(.visible)
            .presentationBackground(.background)
            .presentationCornerRadius(24)
        }
    }
}
