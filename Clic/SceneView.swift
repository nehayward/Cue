import SwiftUI
import SonosKit

struct SceneView: View {
    @Environment(SonosService.self) var sonosService: SonosService
    @State var show: Bool = false

    var scenes: [SonosScene] = []

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(0..<1) { _ in
                    Button {
                        Task {
                            await sonosService.runScene(id: UUID())
                        }
                    } label: {
                        Text("Group All")
                            .padding()
                            .background{
                                Capsule()
                                    .foregroundStyle(.thinMaterial)
                                    .shadow(radius: 2, x: 0, y: 1)
                            }
                            .padding(2)
                    }
                    .buttonStyle(.plain)
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .padding(.trailing, 40)
        .scrollTargetBehavior(.viewAligned)
        .scrollIndicators(.hidden)
        .scrollContentBackground(.hidden)
        .safeAreaInset(edge: .trailing) {
            Button {
                show = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
            }
        }
        .sheet(isPresented: $show) {
            SceneBuilderScreen()
        }
    }
}

#Preview {
    SceneView()
        .environment(SonosService())
}
