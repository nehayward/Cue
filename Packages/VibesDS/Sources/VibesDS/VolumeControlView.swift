//import SwiftUI
//
//public struct VolumeControlView: View {
//    @State private var volumeTask: Task<Void, Error>?
//    @State private var isEditingRoomVolume = false
//    @Binding private var volume: Double
//
//    private var updatedVolume: ((Double) -> Void)? = nil
//    private var setRelativeVolume: ((Double) -> Void)? = nil
//    private var setMute: ((Bool) -> Void)? = nil
//
//    private let delayDrag: Bool
//
//    public init(
//        volume: Binding<Double>,
//        delayDrag: Bool = false,
//        updatedVolume: ((Double) -> Void)? = nil,
//        setRelativeVolume: ((Double) -> Void)? = nil,
//        setMute: ((Bool) -> Void)? = nil
//    ) {
//        self._volume = volume
//        self.delayDrag = delayDrag
//        self.updatedVolume = updatedVolume
//        self.setRelativeVolume = setRelativeVolume
//        self.setMute = setMute
//    }
//
//    public var body: some View {
//        HStack(alignment: .center, spacing: 0) {
//            Button {
//                Task {
//                    setRelativeVolume?(-2)
//                    volume = max(0, volume - 2)
//                }
//            } label: {
//                Image(systemName: "minus")
//                    .frame(width: 24, height: 24)
//                    .bold()
//            }
//            .tint(.primary)
//            .buttonStyle(.liveActivity)
//            .buttonRepeatBehavior(.enabled)
//
//            VibeSlider(value: $volume, in: 0...100, delayDrag: delayDrag) { isEditing in
//                self.isEditingRoomVolume = isEditing
//                let volume = volume
//                updateVolume(volume: volume)
//            }
//            Button {
//                Task {
//                    setRelativeVolume?(2)
//                    volume  = min(100, volume + 2)
//                }
//            } label: {
//                Image(systemName: "plus")
//                    .frame(width: 24, height: 24)
//                    .bold()
//            }
//            .tint(.primary)
//            .buttonStyle(.liveActivity)
//            .buttonRepeatBehavior(.enabled)
//        }
//        .font(.caption)
//        .fontDesign(.rounded)
//        .frame(height: 38)
//    }
//
//    private func updateVolume(volume: Double) {
//        volumeTask?.cancel()
//        volumeTask = Task {
//            try Task.checkCancellation()
//            updatedVolume?(volume)
//        }
//    }
//
//}
//
//fileprivate struct Container: View {
//    @State var volume = 0.0
//    var body: some View {
//        VolumeControlView(volume: $volume)
//    }
//}
//
//#Preview {
//    Container()
//}
//
//#Preview("Colors") {
//    Container(volume: 50)
//        .foregroundStyle(Color.red)
//}
