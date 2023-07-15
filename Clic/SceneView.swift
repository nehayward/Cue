import SwiftUI
import SonosKit

struct SceneView: View {
//    @Environment(SonosService.self) var sonosService: SonosService
    @Binding var show: Bool

    var body: some View {
        ScrollView(.horizontal) {
            HStack {
                ForEach(0..<2) {
                    Text("Garage \($0)")
                        .padding()
                        .foregroundStyle(.primary)
                        .background {
                            Capsule()
                                .foregroundStyle(.background)
                        }
                }
                Button {
                    show = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.largeTitle)
                }
            }
            .fontDesign(.rounded)
            .fontWeight(.bold)
        }
        .scrollClipDisabled()
       
    }
}

#Preview {
    List {
        SceneView(show: .constant(false))

//                .listRowBackground(Color.clear)

    }
}
