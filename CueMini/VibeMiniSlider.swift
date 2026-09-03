import SwiftUI

/// Preference key for tracking width changes efficiently
private struct WidthPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// A custom slider view that provides a visual and interactive representation of a value within a range.
public struct VibeMiniSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme: ColorScheme
    
    @Binding private var value: Double
    @State private var localValue: Double?
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var isTouched: Bool = false
    @State private var isHovered: Bool = false
    
    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private var capsuleColor: Color { colorScheme == .dark ? .white : .black }
    private var capsuleForeground: Color {
      if !showBlendMode {
        colorScheme == .dark ? .black : .white
      } else {
        .white
      }
    }
    private let delayDrag: Bool
    private let showValue: Bool
    private var onEditingChanged: (Bool) -> Void
    private var range: ClosedRange<Double>
    private let step: Double.Stride

    private var showBlendMode: Bool {
      if #available(macOS 26.0, *) {
        false
      } else {
        true
      }
    }


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
        showValue: Bool = false,
        onEditingChanged: @escaping (Bool) -> Void = { _ in }) {
            self._value = value
            self.range = range
            self.step = step
            self.baseHeight = baseHeight
#if targetEnvironment(macCatalyst)
            self.delayDrag = false
#else
            self.delayDrag = delayDrag
#endif
            self.showValue = showValue
            self.onEditingChanged = onEditingChanged
        }
    
    public var body: some View {
        ZStack(alignment: .leading) {
            Capsule()
                .background {
                    GeometryReader { proxy in
                        Color.clear
                            .preference(key: WidthPreferenceKey.self, value: proxy.size.width)
                    }
                }
                .onPreferenceChange(WidthPreferenceKey.self) { newWidth in
                    if width != newWidth {
                        width = newWidth
                    }
                }
            //                .frame(height: isDragging ? expandedHeight : baseHeight)
                .frame(height: baseHeight)
                .foregroundStyle(.quaternary)
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                .shadow(color: .white.opacity(0.1), radius: 0.5, y: 0.5)
                .overlay(alignment: .leading) {
                    Capsule()
                        .overlay {
                            if isDragging {
                                Capsule().foregroundStyle(Color.black.opacity(0.15)).blendMode(.lighten)
                            }
                        }
                        .frame(width: calculateProgressWidth(), height: baseHeight)
                        .animation(isDragging ? nil : .smooth(duration: 0.15), value: displayValue)
                }
                .clipShape(.capsule) // Best attempt at fixing a bug https://twitter.com/ChristianSelig/status/1757139789457829902
#if !os(watchOS) && !os(macOS)
                .contentShape(.hoverEffect, .capsule)
#endif
          Text("\(Int(displayValue))")
            .font(.subheadline)
            .monospacedDigit()
            .fontDesign(.rounded)
            .fontWeight(.heavy)
            .foregroundStyle(isDragging ? AnyShapeStyle(capsuleForeground) : AnyShapeStyle(.white))
            .blendMode(showBlendMode ? .difference : .normal)
            .contentTransition(.identity)
            .frame(minWidth: 28, minHeight: baseHeight)
            .background(isDragging ? capsuleColor : Color.clear)
            .clipShape(.capsule)
            .offset(x: offsetForValue, y: isDragging ? -24 : 0)
            .animation(.interactiveSpring, value: isDragging)
            .animation(isDragging ? nil : .interactiveSpring, value: displayValue)
            .opacity(showValue ? 1 : 0)
        }
        .padding(.vertical, baseHeight/2)
        .gesture(dragGesture)
#if !targetEnvironment(macCatalyst)
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    if !isTouched {
                        isTouched = true
                    }
                }
                .onEnded { _ in
                    isTouched = false
                }
        )
#endif
#if !os(visionOS)
        .sensoryFeedback(trigger: displayValue) { oldValue, newValue in
            guard isDragging else { return .none }
            return oldValue < newValue ? .decrease : .increase
        }
#endif
#if !os(watchOS) && !os(macOS)
        .onHover { hovering in
            if isHovered != hovering {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isHovered = hovering
                }
            }
        }
#endif
        .accessibilityRepresentation {
            Slider(value: $value, in: 0.0...range.upperBound, onEditingChanged: onEditingChanged)
        }
        .opacity(isEnabled ? 1 : 0.5)
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: delayDrag ? 16 : 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }
    
    private func handleDragChanged(_ gesture: DragGesture.Value) {
        if !isDragging {
            isDragging = true
            localValue = value
            onEditingChanged(true)
        }
        calculateNewValue(from: gesture)
    }
    
    private func handleDragEnded(_ gesture: DragGesture.Value) {
#if targetEnvironment(macCatalyst) || os(macOS)
        if gesture.translation.width == 0.0 {
            let newPercentage = gesture.location.x / width
            localValue = min(max(range.lowerBound, newPercentage * range.upperBound), range.upperBound)
        }
#endif
        if let finalValue = localValue {
            value = finalValue
        }
        isDragging = false
        localValue = nil
        onEditingChanged(false)
    }
    
    private func calculateNewValue(from gesture: DragGesture.Value) {
        guard width > 0 else { return }
        let newPercentage = gesture.location.x / width
        let newValue = newPercentage * range.upperBound
        let steppedValue = (newValue / step).rounded() * step
        let clampedValue = min(max(range.lowerBound, steppedValue), range.upperBound)
        localValue = clampedValue
        value = clampedValue
    }
    
    private var innerCirclePadding: CGFloat { expandedHeight * 0.15 }
    
    private var displayValue: Double {
        localValue ?? value
    }
    
    private func calculateProgressWidth() -> CGFloat {
        guard width > 0, range.upperBound > 0 else { return 0 }
        let calculatedWidth = (displayValue / range.upperBound) * width
        return max(0, calculatedWidth)
    }
    
    private var offsetForValue: Double {
        guard width > 0 else { return 0 }
        let progressWidth = calculateProgressWidth()
        return min(max(0, progressWidth - 28), width - 28)
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
