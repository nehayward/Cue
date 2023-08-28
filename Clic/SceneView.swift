import SwiftUI
import SonosKit

struct SceneView: View {
    //    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var show: Bool
    
    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(0..<10) {
                    Text("Garage \($0)")
                        .padding()
                        .foregroundStyle(.primary)
                        .background {
                            Capsule()
                                .foregroundStyle(.thinMaterial)
                        }
                }
            }
            .scrollTargetLayout()
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .padding(.trailing, 40)
        .scrollTargetBehavior(.viewAligned)
        .overlay(alignment: .trailing) {
            Button {
                show = true
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.largeTitle)
            }
            .padding()
            .background {
                RoundedRectangle(cornerRadius: 24)
                    .foregroundStyle(.thinMaterial)
                    .blur(radius: 10)
            }
        }
    }
}

#Preview {
    
    SceneView(show: .constant(false))
        .listRowBackground(Color.clear)
    
    
}
