import SwiftUI
import SonosKit

struct PillView: View {
    @Environment(AlertService.self) var alertService: AlertService
    
    @State private var offset: CGFloat = 0
    
    var body: some View {
        VStack {
            if alertService.alert.isShowing {
                HStack {
                    Text(alertService.alert.text)
                    if let imageName = alertService.alert.imageName {
                        Image(systemName: imageName)
                    }
                }
                .fontDesign(.rounded)
                .bold()
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(Capsule().foregroundStyle(.thickMaterial))
                .shadow(radius: 5)
                .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(alertService.alert.isShowing ? 0.8 : 1)))
                .animation(.bouncy, value: alertService.alert.isShowing)
                .zIndex(1) // Ensure it appears above other content
                .offset(y: -offset)
                .gesture(
                    DragGesture()
                        .onChanged { gesture in
                            if gesture.translation.height < 0 {
                                offset = -gesture.translation.height
                            }
                        }
                        .onEnded { gesture in
                            if gesture.translation.height < -50 {
                                withAnimation {
                                    alertService.alert.isShowing = false
                                    offset = 0
                                }
                            } else {
                                withAnimation {
                                    offset = 0
                                }
                            }
                        }
                )
            }
            
            Spacer() // Push the pill to the top
        }
    }
}

#Preview {
    Text("PillView")
        .safeAreaInset(edge: .top) {
            PillView()
                .environment(AlertService())
        }
}
