import SwiftUI
import SonosKit
import VibesDS

struct AlertView: View {
    @Environment(AlertService.self) var alertService: AlertService
    
    @State private var offset: CGFloat = 0
    @State private var isVisible: Bool = false
    
    var body: some View {
        VStack {
            if alertService.alert.isShowing {
                HStack {
                    if let content = alertService.alert.content {
                        VibeContentArtworkView(content: content)
                            .frame(width: 60, height: 60)
                            .scaleEffect(isVisible ? 1 : 0.5)
                            .opacity(isVisible ? 1 : 0)
                    }
                    VStack(alignment: .leading) {
                        Text(alertService.alert.text)
                        Text(alertService.alert.subtitle)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let imageName = alertService.alert.imageName, !imageName.isEmpty {
                        Image(systemName: imageName)
                    }
                }
                .fontDesign(.rounded)
                .bold()
                .padding()
                .frame(maxWidth: 500, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 18).foregroundStyle(.ultraThinMaterial).shadow(radius: 1))
                .scaleEffect(isVisible ? 1 : 0.6)
                .opacity(isVisible ? 1 : 0)
                .offset(y: isVisible ? 0 : -50)
                .animation(.interactiveSpring, value: isVisible)
                .onAppear {
                    withAnimation {
                        isVisible = true
                    }
                }
                .onDisappear {
                    isVisible = false
                }
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
                .onTapGesture {
                    alertService.alert.handleTap?()
                }
            }
            
            Spacer() // Push the pill to the top
        }
        .padding(.top, 40)
        .padding(.horizontal, 10)
    }
}

#Preview {
    Text("PillView")
        .safeAreaInset(edge: .top) {
            AlertView()
                .environment(AlertService())
        }
}
