import SwiftUI
import Combine
import SonosKitMini

struct MenuBarView: View {
    var sonosService = SonosMiniService.shared
    var sizePassthrough: PassthroughSubject<CGSize, Never>
    
    @State private var isShowingTitle = false
    @State private var currentTitle = ""

    @ViewBuilder
    var mainContent: some View {
        HStack(alignment: .center, spacing: 4) {
            Image(systemName: "hifispeaker.fill")
                .resizable()
                .bold()
                .aspectRatio(contentMode: .fit)
                .frame(width: 14, height: 14)
            
//            Text(sonosService.devices.first?.currentTrackMetadata?.title ?? "UNKNON")
//                .fixedSize()
            if isShowingTitle {
                Text(currentTitle)
                    .fixedSize()
                    .transition(.opacity)
                    .frame(maxWidth: 100)
            }
//            if let group = sonosService.selectedGroup {
//                Text(group.nameWithCount)
//                    .fixedSize()
//                Button {
//                    Task {
//                        await sonosService.togglePlayback(ip: group.ip)
//                    }
//                } label: {
//                    Image(systemName: "play.fill")
//                }
//                .buttonStyle(.plain)
//            } else {
//                Text("Select Group")
//                    .fixedSize()
//            }
        }
        .fontDesign(.rounded)
        .padding(.horizontal, 8)
        .onChange(of: sonosService.devices) {
            let newTitle = sonosService.devices
                .first(where: { $0.transportState.lowercased() == "playing" })?
                .currentTrackMetadata?.title ?? ""
            
            if newTitle != currentTitle, !newTitle.isEmpty {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    isShowingTitle = false
                }
                
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    currentTitle = newTitle
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isShowingTitle = !newTitle.isEmpty
                    }
                }
            }
        }
    }

    var body: some View {
        mainContent
            .overlay(
                GeometryReader { geometryProxy in
                    Color.clear
                        .preference(key: SizePreferenceKey.self, value: geometryProxy.size)
                }
            )
            .onPreferenceChange(SizePreferenceKey.self) { size in
                sizePassthrough.send(size)
            }
    }
}
