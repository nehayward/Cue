import SwiftUI

/// A custom slider view that provides a visual and interactive representation of a value within a range.
@available(tvOS, unavailable)
public struct VibeSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var startingValue: Double?
    @State private var onEditingChangedTask: Task<Void, Error> = Task { }
    @State private var onHover: Bool = false
    @State private var isTouched: Bool = false
    @State private var isHovered: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    
    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private var capsuleColor: Color { colorScheme == .dark ? .white : .black }
    private let delayDrag: Bool
    private let showValue: Bool
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
//                .frame(height: isDragging ? expandedHeight : baseHeight)
                .frame(height: baseHeight)
                .foregroundStyle(
                    .quaternary
                        .shadow(.inner(color: .black.opacity(0.3), radius: 3.0, y: 2.0))
                )
                .shadow(color: .white.opacity(0.2), radius: 1, y: 1)
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
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
                            .frame(width: calculateProgressWidth(), height: baseHeight)
                            .animation(.interactiveSpring, value: value)
                    }
                }
                .clipShape(.capsule) // Best attempt at fixing a bug https://twitter.com/ChristianSelig/status/1757139789457829902
#if !os(watchOS) && !os(macOS)
                .contentShape(.hoverEffect, .capsule)
#endif
            Text("\(Int(value))")
                .monospacedDigit()
                .fontDesign(.rounded)
                .bold()
                .foregroundStyle(.white)
                .blendMode(.difference)
                .frame(minWidth: 28, minHeight: baseHeight)
                .background((isDragging || isTouched) ? capsuleColor : Color.clear)
                .clipShape(.capsule)
                .offset(x: offsetForValue,
                        y: (isTouched || isDragging) ? -24 : 0)
                .opacity(showValue ? 1 : 0)
        }
        .geometryGroup()
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
        .sensoryFeedback(trigger: value) { oldValue, newValue in
            guard isDragging else { return .none }
            return oldValue < newValue ? .decrease : .increase
        }
#endif
#if !os(watchOS) && !os(macOS)
        .hoverEffect(.highlight)
        .defaultHoverEffect(.highlight)
#endif
#if !os(watchOS) && !os(macOS)
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .onContinuousHover { phase in
            switch phase {
            case .active(let location):
                mouseLocation = location
            case .ended:
                mouseLocation = .zero
                break
            }
        }
#endif
        .animation(.interactiveSpring, value: isDragging)
        .animation(.interactiveSpring, value: isTouched)
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
        isDragging = true
        onEditingChanged(true)
        calculateNewValue(from: gesture)
    }
    
    private func handleDragEnded(_ gesture: DragGesture.Value) {
#if targetEnvironment(macCatalyst) || os(macOS)
        if gesture.translation.width == 0.0 {
            let newPercentage = gesture.location.x / width
            value = newPercentage * range.upperBound
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
        return max(0, calculatedWidth)
    }
    
    private var offsetForValue: Double {
        min(max(0, calculateProgressWidth() - 28), width - 28)
    }
}

#Preview {
    @Previewable @State var volume = 12.0
#if !os(tvOS)
    VibeSlider(value: $volume, showValue: true)
        .padding(.horizontal)
#endif
}


import SwiftUI

/// A custom slider view that provides a visual and interactive representation of a value within a range.
public struct VibeSliderTV: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    @Binding private var value: Double
    @State private var width = 0.0
    @State private var isDragging: Bool = false
    @State private var startingValue: Double?
    @State private var onEditingChangedTask: Task<Void, Error> = Task { }
    @State private var onHover: Bool = false
    @State private var isTouched: Bool = false
    @State private var isHovered: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    
    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private var capsuleColor: Color { colorScheme == .dark ? .white : .black }
    private let delayDrag: Bool
    private let showValue: Bool
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
        let _ = Self._printChanges()
        
        ZStack(alignment: .leading) {
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
                .frame(height: baseHeight)
                .foregroundStyle(
                    .quaternary
                        .shadow(.inner(color: .black.opacity(0.3), radius: 3.0, y: 2.0))
                )
                .overlay(alignment: .leading) {
                    ZStack(alignment: .leading) {
                        Capsule()
                            .frame(width: calculateProgressWidth(), height: baseHeight)
                    }
                }
            Text("\(value, specifier: "%03.0f")%")
                .monospacedDigit()
                .fontDesign(.rounded)
                .bold()
                .padding(.vertical, 20)
//                .clipShape(.circle)
                .offset(x: offsetForValue)
                .foregroundStyle(.ultraThickMaterial)
                .opacity(showValue ? 1 : 0)
//            
        }
//        .padding(.vertical, baseHeight/2)
#if !os(visionOS)
        .sensoryFeedback(trigger: value) { oldValue, newValue in
            guard isDragging else { return .none }
            return oldValue < newValue ? .decrease : .increase
        }
#endif
        #if !os(tvOS)
        .accessibilityRepresentation {
            Slider(value: $value, in: 0.0...range.upperBound, onEditingChanged: onEditingChanged)
        }
        #endif
        .opacity(isEnabled ? 1 : 0.5)
    }
    
    @available(tvOS, unavailable)
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: delayDrag ? 16 : 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }
    
    @available(tvOS, unavailable)
    private func handleDragChanged(_ gesture: DragGesture.Value) {
        isDragging = true
        onEditingChanged(true)
        calculateNewValue(from: gesture)
    }
    
    @available(tvOS, unavailable)
    private func handleDragEnded(_ gesture: DragGesture.Value) {
#if targetEnvironment(macCatalyst) || os(macOS)
        if gesture.translation.width == 0.0 {
            let newPercentage = gesture.location.x / width
            value = newPercentage * range.upperBound
        }
#endif
        isDragging = false
        onEditingChanged(false)
        startingValue = nil
    }
    
    @available(tvOS, unavailable)
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
        return max(0, calculatedWidth)
    }
    
    private var offsetForValue: Double {
        min(max(0, calculateProgressWidth() - 80), width - 40)
    }
}

#Preview {
    @Previewable @State var volume = 12.0
#if !os(tvOS)
    VibeSlider(value: $volume, showValue: true)
        .padding(.horizontal)
#endif
}
