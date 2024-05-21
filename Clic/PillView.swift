import SwiftUI
import SonosKit

struct PillView: View {
    @Environment(AlertService.self) var alertService: AlertService

    var body: some View {
        Group {
            if let content = alertService.alert.content {
                PlayableContentView(item: content)
                    .disabled(true)
            } else {
                Label {
                    Text(alertService.alert.text)
                } icon: {
                    Image(systemName: "hifispeaker.fill")
                }
            }
        }
        .padding()
        .background {
            if let content = alertService.alert.content {
                RoundedRectangle(cornerRadius: 12)
                    .foregroundStyle(.thinMaterial)
            } else {
                Capsule()
                    .foregroundStyle(.thickMaterial)
            }
        }
        .frame(alignment: .top)
        .fontDesign(.rounded)
        .bold()
        .transition(.asymmetric(insertion: .move(edge: .top), removal: .identity))
        .offset(y: alertService.alert.isShowing ? 0 : -300)
        .frame(height: 100)
        .shadow(radius: 10)
    }
}

#Preview {
    Text("PillView")
        .safeAreaInset(edge: .top) {
            PillView()
                .environment(AlertService())
        }
}
