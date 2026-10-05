import SwiftUI

/// A custom slider view that provides a visual and interactive representation of a value within a range.
@available(tvOS, unavailable)
public struct VibeSlider: View {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.colorScheme) private var colorScheme: ColorScheme

    @Binding private var value: Double
    @State private var width = 0.0
    @State private var startingValue: Double?
    @State private var onEditingChangedTask: Task<Void, Error> = Task { }
    @State private var onHover: Bool = false
    @State private var isHovered: Bool = false
    @State private var mouseLocation: CGPoint = .zero
    /// False until `value` has changed once. The first change is the slider
    /// catching up to the real level (a speaker's volume arriving after the
    /// row appears), so it jumps there instead of sweeping up from 0. Until
    /// then the fill and label take no animation at all, inherited ones
    /// included.
    @State private var animatesValue = false
    
    @GestureState private var isDragGestureActive: Bool = false
    /// A UIKit drag (`SidewaysPan`) is moving the slider.
    @State private var isHolding: Bool = false
    /// A long press is down: until it lifts, the drag beside it moves
    /// nothing, so a press held into a slide can't edit (and unmute) what
    /// it just muted.
    @State private var isLongPressing: Bool = false
    /// Where the SwiftUI drag's touch is, while `onLongPress` is set.
    @State private var press: Press = .idle
    @State private var pressTimer: Task<Void, Never>?
    /// A press held still (or one that became the long press) isn't a drag,
    /// so the value doesn't rise and the fill doesn't darken under it.
    private var isDragging: Bool {
        isHolding || (isDragGestureActive && press != .holding && press != .longPressed)
    }

    /// A touch on the SwiftUI path when the slider has a long press: it
    /// isn't an edit until it moves past the slop, and once the long press
    /// fires it never is.
    private enum Press: Equatable {
        case idle
        case holding
        /// Editing, measured from this far across, where the slop ended.
        case editing(from: CGFloat)
        case longPressed
    }

    /// How far a held finger may drift before it's a drag.
    private static let slop: CGFloat = 4

    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private var capsuleColor: Color { colorScheme == .dark ? .white : .black }
    private let delayDrag: Bool
    private let showValue: Bool
    private var onEditingChanged: (Bool) -> Void
    private let onLongPress: (() -> Void)?
    private var range: ClosedRange<Double>
    private let step: Double.Stride
    private let valueAnimation: Animation?
    /// Every division by the range goes through here — see `SliderMath`.
    private var math: SliderMath { SliderMath(range: range) }

    /// Initializes a new instance of `VibeSlider`.
    /// - Parameters:
    ///   - value: A binding to the value represented by the slider.
    ///   - range: The range of values the slider can represent.
    ///   - step: The smallest discrete value change allowed.
    ///   - delayDrag: For sliders in lists. Before iOS 18 the drag waits for a
    ///     16 pt dead zone; from iOS 18 it's a `SidewaysPan`, which starts
    ///     only sideways and makes the list wait, with no dead zone.
    ///   - valueAnimation: How the fill moves when `value` changes. Pass `nil`
    ///     to have it swap in place instead — the animation is applied inside
    ///     the slider, so a caller cannot suppress it with a transaction from
    ///     the outside.
    ///   - onEditingChanged: A closure called when editing begins and ends.
    ///   - onLongPress: Called when the slider is held still for half a
    ///     second (the volume sliders mute with it). A held touch then never
    ///     starts an edit. iPhone and iPad only; the Mac right-clicks.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...100,
        step: Double.Stride = 1,
        baseHeight: CGFloat = 24,
        delayDrag: Bool = false,
        showValue: Bool = false,
        valueAnimation: Animation? = .interactiveSpring,
        onEditingChanged: @escaping (Bool) -> Void = { _ in },
        onLongPress: (() -> Void)? = nil) {
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
            self.valueAnimation = valueAnimation
            self.onEditingChanged = onEditingChanged
            self.onLongPress = onLongPress
        }
    
    public var body: some View {
        dragHandling(track)
#if !os(visionOS)
        .sensoryFeedback(trigger: value) { oldValue, newValue in
            guard isDragging else { return .none }
            return oldValue < newValue ? .decrease : .increase
        }
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
        .accessibilityRepresentation {
            // The value clamped as well as the range made safe: a radio
            // position runs past its zero duration, and the system slider
            // should not be handed a value outside its bounds either.
            Slider(value: Binding(get: { math.clamped(value) }, set: { value = $0 }), in: math.safeRange, onEditingChanged: onEditingChanged)
        }
        .opacity(isEnabled ? 1 : 0.5)
        .onChange(of: value) {
            guard !animatesValue else { return }
            // Deferred so the change that triggered this still renders
            // without animation.
            Task { @MainActor in animatesValue = true }
        }
        // A slider taken away under a held finger mustn't fire its long
        // press later for a row that's gone.
        .onDisappear {
            if press != .idle {
                finishPress()
            }
        }
        .onChange(of: isDragGestureActive) { _, active in
            guard !active, press != .idle else { return }
            // A drag the system took away (a scroll claiming it, a sheet
            // closing) resets its gesture state and never calls `onEnded`:
            // finish the press here, a turn later so a normal end goes first.
            Task { @MainActor in
                guard !isDragGestureActive, press != .idle else { return }
                finishPress()
            }
        }
    }

    private var track: some View {
        ZStack(alignment: .leading) {
            // visionOS (on device) does not like when drag targets are smaller than 40pt tall, so add an almost-transparent (as it still needs to be interactive) that enforces an effective minimum height. If the slider is tall than this on its own it's essentially just ignored.
#if os(visionOS)
            Color.orange.opacity(0.0001)
                .frame(height: 40.0)
#endif
            Capsule()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .frame(height: baseHeight)
                .foregroundStyle(.quaternary)
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                .shadow(color: .white.opacity(0.1), radius: 0.5, y: 0.5)
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
                            .animation(fillAnimation, value: value)
                            // Until the first value lands, also drop animations
                            // inherited from outside: a list animating rows in
                            // otherwise grows the fill from width 0.
                            .transaction { if !animatesValue { $0.animation = nil } }
                    }
                }
                .clipShape(.capsule) // Best attempt at fixing a bug https://twitter.com/ChristianSelig/status/1757139789457829902
#if !os(watchOS) && !os(macOS)
                .contentShape(.hoverEffect, .capsule)
#endif
            Text("\(Int(math.clamped(value)))")
#if targetEnvironment(macCatalyst)
                .font(.subheadline)
#endif
                .monospacedDigit()
                .fontDesign(.rounded)
                .fontWeight(.semibold)
                .foregroundStyle(.white)
                .blendMode(.difference)
                .contentTransition(.identity)
                .frame(minWidth: 28, minHeight: baseHeight)
                .background(isDragging ? capsuleColor : Color.clear)
                .clipShape(.capsule)
                .offset(x: offsetForValue, y: isDragging ? -24 : 0)
                .opacity(showValue ? 1 : 0)
                .animation(.interactiveSpring, value: isDragging)
                .animation(fillAnimation, value: value)
                .transaction { if !animatesValue { $0.animation = nil } }
        }
        .padding(.vertical, baseHeight/2)
    }

    /// Attaches the drag.
    ///
    /// On iOS 18 a slider in a list (`delayDrag`) drags with `SidewaysPan`
    /// (VibesDS): it only begins sideways, and the list's scroll and a
    /// sheet's pull to dismiss wait for it, so a vertical swipe that starts
    /// on the slider still scrolls and a sideways one never does, with no
    /// dead zone. `onLongPress` is a long-press recognizer beside it. Every
    /// other slider, and older systems, keep the SwiftUI drag, which starts
    /// the moment a finger lands.
    @ViewBuilder
    private func dragHandling(_ content: some View) -> some View {
#if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            if !delayDrag {
                swiftUIDragHandling(content)
            } else if let onLongPress {
                // Enabled through the recognizer rather than by swapping this
                // branch, so a press under way when the slider is disabled is
                // cancelled (and `isLongPressing` cleared), not torn out.
                content
                    .gesture(sidewaysDrag)
                    .gesture(SliderLongPress(isEnabled: isEnabled, onBegan: {
                        isLongPressing = true
                        onLongPress()
                    }, onEnded: {
                        isLongPressing = false
                    }))
            } else {
                content.gesture(sidewaysDrag)
            }
        } else {
            swiftUIDragHandling(content)
        }
#else
        swiftUIDragHandling(content)
#endif
    }

    private func swiftUIDragHandling(_ content: some View) -> some View {
        content
            .gesture(dragGesture)
#if !targetEnvironment(macCatalyst)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .updating($isDragGestureActive) { _, state, _ in
                        state = true
                    }
            )
#endif
    }

#if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 18.0, *)
    private var sidewaysDrag: SidewaysPan {
        SidewaysPan(isEnabled: isEnabled, onBegan: {}, onChanged: { translation in
            guard !isLongPressing else { return }
            isHolding = true
            onEditingChanged(true)
            moveValue(by: translation)
        }, onEnded: {
            guard isHolding else { return }
            isHolding = false
            onEditingChanged(false)
            startingValue = nil
        })
    }
#endif

    /// The SwiftUI path waits for a long press only on a touch screen; the
    /// Mac's long press is the caller's right click.
    private var waitsForLongPress: Bool {
#if os(iOS) && !targetEnvironment(macCatalyst)
        return onLongPress != nil && isEnabled
#else
        return false
#endif
    }
    
    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: delayDrag ? 16 : 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }
    
    private func handleDragChanged(_ gesture: DragGesture.Value) {
        // A touch that started on the long-press path stays on it, even if
        // the slider stops waiting for one partway through.
        guard press != .idle || waitsForLongPress else {
            onEditingChanged(true)
            moveValue(by: gesture.translation.width)
            return
        }
        let moved = gesture.translation
        switch press {
        case .idle, .holding:
            if press == .idle {
                press = .holding
                startPressTimer()
            }
            guard max(abs(moved.width), abs(moved.height)) > Self.slop else { return }
            pressTimer?.cancel()
            press = .editing(from: moved.width)
            onEditingChanged(true)
        case let .editing(from):
            onEditingChanged(true)
            moveValue(by: moved.width - from)
        case .longPressed:
            break
        }
    }
    
    private func handleDragEnded(_ gesture: DragGesture.Value) {
        guard press != .idle || waitsForLongPress else {
#if targetEnvironment(macCatalyst) || os(macOS)
            if gesture.translation.width == 0.0, width > 0 {
                value = math.value(atFraction: gesture.location.x / width)
            }
#endif
            onEditingChanged(false)
            startingValue = nil
            return
        }
        finishPress()
    }

    /// Fires the long press if the finger is still down and still hasn't
    /// moved half a second on.
    private func startPressTimer() {
        pressTimer?.cancel()
        let onLongPress = onLongPress
        pressTimer = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled, press == .holding, isDragGestureActive else { return }
            press = .longPressed
            onLongPress?()
        }
    }

    /// The end of a touch on the long-press path: only an edit has anything
    /// to end.
    private func finishPress() {
        pressTimer?.cancel()
        pressTimer = nil
        if case .editing = press {
            onEditingChanged(false)
            startingValue = nil
        }
        press = .idle
    }
    
    /// Moves the value `translation` points along the track from where the
    /// drag began.
    private func moveValue(by translation: CGFloat) {
        if startingValue == nil {
            startingValue = value
        }
        self.value = math.value(from: startingValue ?? value, translation: translation, trackWidth: width, step: step)
    }
    
    /// No animation while the pointer is on the slider: a spring re-targeted
    /// on every drag tick trails the finger, which reads as lag. Values that
    /// arrive from outside (a speaker event, a button) still animate.
    /// `startingValue` rather than `isDragging`, which Mac Catalyst never sets.
    /// Nothing before the first value lands (see `animatesValue`).
    private var fillAnimation: Animation? {
        guard animatesValue else { return nil }
        return startingValue == nil ? valueAnimation : nil
    }

    private var innerCirclePadding: CGFloat { expandedHeight * 0.15 }
    
    private func calculateProgressWidth() -> CGFloat {
        math.fillWidth(for: value, trackWidth: width)
    }
    
    private var offsetForValue: Double {
        min(max(0, calculateProgressWidth() - 28), max(0, width - 28))
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
    /// Every division by the range goes through here — see `SliderMath`.
    private var math: SliderMath { SliderMath(range: range) }

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
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
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
                            .animation(.interactiveSpring, value: value)
                    }
                }
            Text("\(Int(math.clamped(value)))")
                .font(.caption)
                .monospacedDigit()
                .fontDesign(.rounded)
                .fontWeight(.semibold)
                .contentTransition(.identity)
                .padding(.vertical, 20)
//                .clipShape(.circle)
                .offset(x: offsetForValue)
                .foregroundStyle(.ultraThickMaterial)
                .opacity(showValue ? 1 : 0)
                .animation(.interactiveSpring, value: value)
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
            Slider(value: Binding(get: { math.clamped(value) }, set: { value = $0 }), in: math.safeRange, onEditingChanged: onEditingChanged)
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
        if gesture.translation.width == 0.0, width > 0 {
            value = math.value(atFraction: gesture.location.x / width)
        }
#endif
        isDragging = false
        onEditingChanged(false)
        startingValue = nil
    }
    
    @available(tvOS, unavailable)
    private func calculateNewValue(from gesture: DragGesture.Value) {
        if startingValue == nil {
            startingValue = value
        }
        self.value = math.value(from: startingValue ?? value, translation: gesture.translation.width, trackWidth: width, step: step)
    }
    
    private var innerCirclePadding: CGFloat { expandedHeight * 0.15 }
    
    private func calculateProgressWidth() -> CGFloat {
        math.fillWidth(for: value, trackWidth: width)
    }
    
    private var offsetForValue: Double {
        min(max(0, calculateProgressWidth() - 40), max(0, width - 30))
    }
}

#Preview {
    @Previewable @State var volume = 12.0
#if !os(tvOS)
    VibeSlider(value: $volume, showValue: true)
        .padding(.horizontal)
#endif
}

#if os(iOS) && !targetEnvironment(macCatalyst)
/// A slider held still for half a second, beside its `SidewaysPan`. A drag
/// that sets off sideways first moves it past `allowableMovement` and fails
/// it, and once the pan has begun the press can't.
@available(iOS 18.0, *)
private struct SliderLongPress: UIGestureRecognizerRepresentable {
    var isEnabled = true
    let onBegan: () -> Void
    /// The press lifted, or was taken away.
    let onEnded: () -> Void

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0.5
        press.allowableMovement = 10
        return press
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            onBegan()
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }
}
#endif
