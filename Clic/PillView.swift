import SwiftUI
import SonosKit

struct PillView: View {
    @Environment(AlertService.self) var alertService: AlertService

    var body: some View {
        Label(alertService.alert.text, systemImage: "hifispeaker.fill")
            .padding()
            .background {
                Capsule()
                    .foregroundStyle(.thickMaterial)
            }
            .task {
                try? await Task.sleep(for: .seconds(3))
                alertService.alert.isShowing = false
            }
            .frame(alignment: .top)
            .fontDesign(.rounded)
            .symbolRenderingMode(.hierarchical)
            .bold()
            .transition(.asymmetric(insertion: .move(edge: .top), removal: .identity))
            .offset(y: alertService.alert.isShowing ? 0 : -300)
    }
}

#Preview {
    Text("PillView")
        .safeAreaInset(edge: .top) {
            PillView()
                .environment(AlertService())
        }
}
