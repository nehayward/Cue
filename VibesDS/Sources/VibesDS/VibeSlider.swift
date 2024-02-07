import SwiftUI

/// A custom slider view that provides a visual and interactive representation of a value within a range.
public struct VibeSlider: View {
    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var startingValue: Double?
    @State private var onEditingChangedTask: Task<Void, Error> = Task { }

    private let touchDelay: TimeInterval
    private var onEditingChanged: (Bool) -> Void
    private var cornerRadius: Double { isDragging ? 50 : 12 }
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
        touchDelay: TimeInterval = 0,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self._value = value
            self.range = range
            self.step = step
            self.touchDelay = touchDelay
            self.onEditingChanged = onEditingChanged
        }

    public var body: some View {
#if os(visionOS)
        Slider(value: $value, in: range, step: step) { value in
            onEditingChangedTask.cancel()
            onEditingChangedTask = Task { @MainActor in
                onEditingChanged(value)
            }
        }
        .animation(.interactiveSpring, value: value)
#else
        Group {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .foregroundStyle(.quaternary)
                    Rectangle()
                        .frame(width: geometry.size.width * CGFloat(self.value / range.upperBound))
                }
                .delaysTouches(for: touchDelay) { }
                .gesture(dragGesture)
                .cornerRadius(cornerRadius)
                .onChange(of: geometry.size.width, initial: true) {
                    width = geometry.size.width
                }
                .sensoryFeedback(trigger: value) { oldValue, newValue in
                    guard isDragging else { return .none }
                    return oldValue < newValue ? .decrease : .increase
                }
            }
        }
        .frame(height: isDragging ? 20 : 10)
        .animation(.interactiveSpring, value: value)
        .animation(.interactiveSpring, value: isDragging)
        .fixedSize(horizontal: false, vertical: true)
#endif
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }

    private func handleDragChanged(_ gesture: DragGesture.Value) {
        isDragging = true
        onEditingChanged(true)
        calculateNewValue(from: gesture)
    }

    private func handleDragEnded(_ gesture: DragGesture.Value) {
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
}

fileprivate struct Container: View {
    @State var volume = 0.0
    var body: some View {
        VStack {
            Text(volume, format: .number)
            Slider(value: $volume, in: 0...100, step: 2)
            VibeSlider(value: $volume)
                .padding()
        }
    }
}

#Preview {
    Container()
}

#Preview("Colors") {
    Container(volume: 50)
        .foregroundStyle(Color.red)
}


extension View {
    /// Delays touches for a specified duration before recognizing a gesture or tap.
    /// - Parameters:
    ///   - duration: The time to delay before recognizing the gesture or tap.
    ///   - action: A closure to execute when the tap is recognized.
    func delaysTouches(for duration: TimeInterval = 0.25, onTap action: @escaping () -> Void = {}) -> some View {
        modifier(DelaysTouches(duration: duration, action: action))
    }
}

fileprivate struct DelaysTouches: ViewModifier {
    @State private var disabled = false
    @State private var touchDownDate: Date? = nil

    var duration: TimeInterval
    var action: () -> Void

    func body(content: Content) -> some View {
        Button(action: action) {
            content
        }
        .buttonStyle(DelaysTouchesButtonStyle(disabled: $disabled, duration: duration, touchDownDate: $touchDownDate))
        .disabled(disabled)
    }
}

fileprivate struct DelaysTouchesButtonStyle: ButtonStyle {
    @Binding var disabled: Bool
    var duration: TimeInterval
    @Binding var touchDownDate: Date?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { old, new in
                handleIsPressed(new)
            }
    }

    private func handleIsPressed(_ isPressed: Bool) {
        if isPressed {
            let date = Date()
            touchDownDate = date

            DispatchQueue.main.asyncAfter(deadline: .now() + max(duration, 0)) {
                if date == touchDownDate {
                    disabled = true
                    DispatchQueue.main.async {
                        disabled = false
                    }
                }
            }
        } else {
            touchDownDate = nil
            disabled = false
        }
    }
}
