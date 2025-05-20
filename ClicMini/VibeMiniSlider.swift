import SwiftUI

/// A custom slider view that provides a visual and interactive representation of a value within a range.
public struct VibeMiniSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var startingValue: Double?
    @State private var onEditingChangedTask: Task<Void, Error> = Task { }
    @State private var onHover: Bool = false

    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private let delayDrag: Bool
    private var onEditingChanged: (Bool) -> Void
    private var range: ClosedRange<Double>
    private let step: Double.Stride

    /// Initializes a new instance of `VibeSlider`.
    /// - Parameters:
    ///   - value: A binding to the value represented by the slider.
    ///   - range: The range of values the slider can represent.
    ///   - step: The smallest discrete value change allowed.
    ///   - touchDelay: The delay before recognizing a touch as a drag gesture.
    ///   - onEditingChanged: A closure called when editing begins and ends.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...100,
        step: Double.Stride = 1,
        baseHeight: CGFloat = 24,
        delayDrag: Bool = false,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self._value = value
            self.range = range
            self.step = step
            self.baseHeight = baseHeight
            self.delayDrag = delayDrag
            self.onEditingChanged = onEditingChanged
        }

    public var body: some View {
        ZStack {
            // visionOS (on device) does not like when drag targets are smaller than 40pt tall, so add an almost-transparent (as it still needs to be interactive) that enforces an effective minimum height. If the slider is tall than this on its own it's essentially just ignored.
            #if os(visionOS)
            Color.orange.opacity(0.0001)
                .frame(height: 40.0)
            #endif
            Capsule()
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .onChange(of: proxy.size.width, initial: true) {
                                width = proxy.size.width
                            }
                    }
                }
                .frame(height: isDragging ? expandedHeight : baseHeight)
                .foregroundStyle(
                    .quaternary
                        .shadow(.inner(color: .black.opacity(0.3), radius: 3.0, y: 2.0))
                )
                .shadow(color: .white.opacity(0.2), radius: 1, y: 1)
                .overlay(alignment: .leading) {
                    Capsule()
                        .overlay {
                            if isDragging {
                                Capsule().foregroundStyle(Color.black.opacity(0.15)).blendMode(.lighten)
                            }
                        }
                        #if os(visionOS)
                        .overlay(alignment: .trailing) {
                            ZStack {
                                Circle()
                                    .foregroundStyle(Color.white)
                                    .shadow(radius: 1.0)
                                    .padding(innerCirclePadding)
                                    .opacity(isDragging ? 1.0 : 0.0)
                            }
                        }
                        #endif
                        .frame(width: calculateProgressWidth(), height: isDragging ? expandedHeight : baseHeight)
                }
                .clipShape(.capsule) // Best attempt at fixing a bug https://twitter.com/ChristianSelig/status/1757139789457829902
            #if !os(watchOS) && !os(macOS)
                .contentShape(.hoverEffect, .capsule)
            #endif
            }
        .gesture(dragGesture)
        #if !os(visionOS)
        .sensoryFeedback(trigger: value) { oldValue, newValue in
            guard isDragging else { return .none }
            return oldValue < newValue ? .decrease : .increase
        }
        #endif
        #if !os(watchOS) && !os(macOS)
        .hoverEffect(.highlight)
        .defaultHoverEffect(.highlight)
        #endif
        .accessibilityRepresentation {
            Slider(value: $value, in: 0.0...range.upperBound, onEditingChanged: onEditingChanged)
        }
        .opacity(isEnabled ? 1 : 0.5)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: delayDrag ? 20 : 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ gesture: DragGesture.Value) {
        isDragging = true
        onEditingChanged(true)
        calculateNewValue(from: gesture)
    }

    private func handleDragEnded(_ gesture: DragGesture.Value) {
#if targetEnvironment(macCatalyst) || os(macOS)
        if gesture.translation.width == 0.0 {
            let newPercentage = gesture.location.x / width
            value = newPercentage * 100
        }
#endif
        isDragging = false
        onEditingChanged(false)
        startingValue = nil
    }

    private func calculateNewValue(from gesture: DragGesture.Value) {
        let diff = max(min(gesture.translation.width, width), -width) / width * range.upperBound
        let stepValue = (diff / step).rounded() * step
        if startingValue == nil {
            startingValue = value
        }
        self.value = min(max(range.lowerBound, (startingValue ?? value) + stepValue), range.upperBound)
    }

    private var innerCirclePadding: CGFloat { expandedHeight * 0.15 }

    private func calculateProgressWidth() -> CGFloat {
        let calculatedWidth = (value / range.upperBound) * width
        // Don't let the bar get so small that it disappears
        return max(0, calculatedWidth)
    }
}

#Preview("Colors") {
    @Previewable @State var volume = 0.0

    VStack {
        Text(volume, format: .number)
        Slider(value: $volume, in: 0...100, step: 2)
        VibeMiniSlider(value: $volume)
            .padding()
    }
}
