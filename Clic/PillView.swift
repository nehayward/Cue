import SwiftUI
import SonosKit

struct PillView: View {
    @Environment(AlertService.self) var alertService: AlertService

    var body: some View {
        VStack {
            if alertService.alert.isShowing {
                Text(alertService.alert.text)
                    .padding()
                    .background(Capsule().foregroundStyle(.thickMaterial))
                    .frame(alignment: .top)
                    .fontDesign(.rounded)
                    .bold()
                    .frame(height: 100)
                    .shadow(radius: 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.spring(), value: alertService.alert.isShowing)
    }
}

#Preview {
    Text("PillView")
        .safeAreaInset(edge: .top) {
            PillView()
                .environment(AlertService())
        }
}
