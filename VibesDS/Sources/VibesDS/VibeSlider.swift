import SwiftUI

public struct VibeSlider: View {
    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var previousDragPercentage: Double?

    private let touchDelay: TimeInterval
    private var onEditingChanged: (Bool) -> Void
    private var cornerRadius: Double { isDragging ? 50 : 12 }
    private var range: ClosedRange<Double>

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...100,
        touchDelay: TimeInterval = 0,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self._value = value
            self.range = range
            self.touchDelay = touchDelay
            self.onEditingChanged = onEditingChanged
        }

    public var body: some View {
        Group {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .foregroundStyle(.quaternary)
                        .delaysTouches(for: touchDelay) { }
                        .gesture(holdAndDragGesture)
                    Rectangle()
                        .frame(width: geometry.size.width * CGFloat(self.value / range.upperBound))
                        .allowsHitTesting(false)
                }
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
        .frame(height: isDragging ? 16 : 8)
        .animation(.interactiveSpring, value: value)
        .animation(.interactiveSpring, value: isDragging)
        .fixedSize(horizontal: false, vertical: true)
    }

    var holdAndDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                onEditingChanged(true)
                // Update add to existing location
                var change = 0.0
                let diff = max(min(gesture.translation.width, width), -width)
                let percent = (diff + width) / width
                
                if let previousDragPercentage {
                    change = previousDragPercentage.distance(to: percent)
                }

                let newValue = min(max(range.lowerBound, Double(value + change * range.upperBound)), range.upperBound).rounded(.toNearestOrAwayFromZero)
                self.value = newValue
                isDragging = true
                previousDragPercentage = percent
            }
            .onEnded { value in
                isDragging = false
                onEditingChanged(false)
                previousDragPercentage = nil
            }
    }
}

fileprivate struct Container: View {
    @State var volume = 0.0
    var body: some View {
        VibeSlider(value: $volume)
            .padding()
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
            .onChange(of: configuration.isPressed, handleIsPressed)
    }

    private func handleIsPressed(_ old: Bool, _ new: Bool) {
        if new {
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
