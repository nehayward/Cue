import UIKit
import SwiftUI

public struct VolumeControlView: View {
    @State private var volumeTask: Task<Void, Error>?
    @State private var isEditingRoomVolume = false
    @Binding private var volume: Double

    private var updatedVolume: ((Double) -> Void)? = nil
    private let touchDelay: TimeInterval

    public init(
        volume: Binding<Double>,
        touchDelay: TimeInterval = 0,
        updatedVolume: ((Double) -> Void)? = nil
    ) {
        self._volume = volume
        self.touchDelay = touchDelay
        self.updatedVolume = updatedVolume
    }

    public var body: some View {
        HStack(alignment: .center, spacing: 0) {
            Image(systemName: "speaker.wave.3.fill", variableValue: volume/100)
                .renderingMode(.template)
                .padding(.trailing, 8)
            VibeSlider(value: $volume, in: 0...100, touchDelay: touchDelay) { isEditing in
                self.isEditingRoomVolume = isEditing
                let volume = volume
                updateVolume(volume: volume)
            }
            Text("\(volume, specifier: "%03.0f")%")
                .contentTransition(.numericText())
                .monospacedDigit()
                .animation(.spring.speed(2), value: volume)
                .frame(width: 36, alignment: .trailing)
                .fontDesign(.rounded)
        }
        .font(.caption)
        .fontDesign(.rounded)
        .animation(.interactiveSpring, value: volume)
        .frame(height: 38)
    }

    private func updateVolume(volume: Double) {
        volumeTask?.cancel()
        volumeTask = Task {
            try Task.checkCancellation()
            updatedVolume?(volume)
        }
    }

}

fileprivate struct Container: View {
    @State var volume = 0.0
    var body: some View {
        VolumeControlView(volume: $volume)
    }
}

#Preview {
    Container()
}

#Preview("Colors") {
    Container(volume: 50)
        .foregroundStyle(Color.red)
}
