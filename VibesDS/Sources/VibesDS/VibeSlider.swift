import SwiftUI

public struct VibeSlider: View {
    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var previousDragPercentage: Double?

    private var onEditingChanged: (Bool) -> Void
    private var cornerRadius: Double { isDragging ? 50 : 12 }
    private var range: ClosedRange<Double>

    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...100,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self._value = value
            self.range = range
            self.onEditingChanged = onEditingChanged
        }

    public var body: some View {
        Group {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .foregroundStyle(.quaternary)
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

