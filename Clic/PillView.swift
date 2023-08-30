import SwiftUI
import SonosKit

struct PillView: View {
    @Bindable var alert: Alert

    var body: some View {
        if alert.isShowing {
            Text(alert.text)
                .padding()
                .background {
                    Capsule()
                        .foregroundStyle(.ultraThinMaterial)
                }
                .transition(.push(from: .top).combined(with: .scale))
                .task {
                    try? await Task.sleep(for: .seconds(3))
                    withAnimation {
                        alert.isShowing = false
                    }
                }
                .frame(alignment: .top)
        }
    }
}

#Preview {
    PillView(alert: Alert())
}
