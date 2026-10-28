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
    @State private var labelWidth: CGFloat = 28
    /// False until `value` has changed once. The first change is the slider
    /// catching up to the real level (a speaker's volume arriving after the
    /// row appears), so it jumps there instead of sweeping up from 0. Until
    /// then the fill and label take no animation at all, inherited ones
    /// included.
    @State private var animatesValue = false
    
    @GestureState private var isDragGestureActive: Bool = false
    @State private var isHolding: Bool = false
    /// A long press is down: until it lifts, the drag beside it moves
    /// nothing, so a press held into a slide can't edit (and unmute) what
    /// it just muted.
    @State private var isLongPressing: Bool = false
    private var isDragging: Bool { isDragGestureActive || isHolding }

    private let baseHeight: Double
    private var expandedHeight: Double { baseHeight * 1.65 }
    private var capsuleColor: Color { colorScheme == .dark ? .white : .black }
    private let delayDrag: Bool
    private let immediateDrag: Bool
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
    ///   - delayDrag: For sliders in lists: the drag only begins once it has
    ///     gone sideways past a dead zone. Only before iOS 18; from iOS 18
    ///     every slider's drag is `SidewaysPan`, which starts sideways only
    ///     and makes the list wait, with no dead zone.
    ///   - immediateDrag: Start the drag on touch-down so a navigation back
    ///     swipe can't claim it first. Only for sliders outside scroll views —
    ///     it also stops a scroll that starts on the slider. iOS 18+.
    ///   - valueAnimation: How the fill moves when `value` changes. Pass `nil`
    ///     to have it swap in place instead — the animation is applied inside
    ///     the slider, so a caller cannot suppress it with a transaction from
    ///     the outside.
    ///   - onEditingChanged: A closure called when editing begins and ends.
    ///   - onLongPress: Called when the slider is held still for half a
    ///     second (the volume sliders mute with it). A held touch then never
    ///     starts an edit. iOS 18+.
    public init(
        value: Binding<Double>,
        in range: ClosedRange<Double> = 0...100,
        step: Double.Stride = 1,
        baseHeight: CGFloat = 24,
        delayDrag: Bool = false,
        immediateDrag: Bool = false,
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
            self.immediateDrag = immediateDrag
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
                // A step lighter under a pointer, the Mac's in particular,
                // where nothing else shows the slider is under it.
                .foregroundStyle(isHovered && isEnabled ? .tertiary : .quaternary)
                .shadow(color: .black.opacity(0.1), radius: 1.5, y: 1)
                .shadow(color: .white.opacity(0.1), radius: 0.5, y: 0.5)
                .overlay(alignment: .leading) {
                    // Laid out as its share of the track, not from `width`,
                    // which is measured after layout: as the track grows or
                    // shrinks in an animation (a panel opening beside the
                    // player), the fill moves with it rather than jumping to
                    // its new width once the measure comes in.
                    LeadingFraction(fraction: math.fraction(of: value)) {
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
                            .frame(height: baseHeight)
                    }
                    .animation(fillAnimation, value: value)
                    // Until the first value lands, also drop animations
                    // inherited from outside: a list animating rows in
                    // otherwise grows the fill from width 0.
                    .transaction { if !animatesValue { $0.animation = nil } }
                }
                .clipShape(.capsule) // Best attempt at fixing a bug https://twitter.com/ChristianSelig/status/1757139789457829902
#if !os(watchOS) && !os(macOS)
                .contentShape(.hoverEffect, .capsule)
#endif
            // Not built at all when hidden: the scrub bar's value ticks with
            // playback, and an invisible label still costs layout every tick.
            if showValue {
                // Placed along the track by layout, as the fill is, so it
                // keeps to the fill's end as the track's width animates.
                ValueLabelPlacement(fraction: math.fraction(of: value), inset: 28) {
                    valueLabel
                        .frame(minWidth: 28, minHeight: baseHeight)
                        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { labelWidth = $0 }
                        .background(isDragging ? capsuleColor : Color.clear)
                        .clipShape(.capsule)
                }
                .offset(y: isDragging ? -24 : 0)
                .animation(.interactiveSpring, value: isDragging)
                .animation(fillAnimation, value: value)
                .transaction { if !animatesValue { $0.animation = nil } }
            }
        }
        .padding(.vertical, baseHeight/2)
    }

    /// Attaches the drag to the slider.
    ///
    /// On iOS 18+ the drag is a UIKit recognizer, because SwiftUI's
    /// `DragGesture` can't pick a direction or defer to other recognizers:
    /// - `immediateDrag` begins on touch-down (`TouchDownDrag`), so the
    ///   navigation stack's full-screen back swipe (iOS 26) can't claim the
    ///   touch first — behind it the slider read as having a minimum drag
    ///   distance.
    /// - Every other slider is a `SidewaysPan`: it only begins sideways, and
    ///   the list's scroll, a sheet's pull to dismiss and the back swipe wait
    ///   for it, so a vertical swipe that starts on the slider still scrolls
    ///   and a sideways one never does. That retired `delayDrag`'s dead zone.
    ///   `onLongPress` is a long-press recognizer beside it.
    /// The Mac, visionOS and older systems keep the SwiftUI path.
    @ViewBuilder
    private func dragHandling(_ content: some View) -> some View {
#if os(iOS) && !targetEnvironment(macCatalyst)
        if #available(iOS 18.0, *) {
            // The recognizers are told `isEnabled` themselves: `.disabled`
            // isn't known to reach a UIKit one.
            if immediateDrag {
                content.gesture(touchDownDrag)
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

#if os(iOS) && !targetEnvironment(macCatalyst)
    @available(iOS 18.0, *)
    private var touchDownDrag: TouchDownDrag {
        TouchDownDrag(
            isEnabled: isEnabled,
            onChanged: uiKitDragChanged,
            onEnded: uiKitDragEnded,
            onLongPress: onLongPress
        )
    }

    @available(iOS 18.0, *)
    private var sidewaysDrag: SidewaysPan {
        SidewaysPan(isEnabled: isEnabled, onBegan: {}, onChanged: uiKitDragChanged, onEnded: uiKitDragEnded)
    }

    private func uiKitDragChanged(_ translation: CGFloat) {
        guard !isLongPressing else { return }
        isHolding = true
        applyDrag(translation: translation)
    }

    private func uiKitDragEnded() {
        guard isHolding else { return }
        isHolding = false
        onEditingChanged(false)
        startingValue = nil
    }
#endif

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
    
    private var valueText: some View {
        Text("\(Int(math.clamped(value)))")
#if targetEnvironment(macCatalyst)
            .font(.subheadline)
#endif
            .monospacedDigit()
            .fontDesign(.rounded)
            .fontWeight(.semibold)
            .contentTransition(.identity)
            .frame(minWidth: 28, minHeight: baseHeight)
    }

    /// The value readout, drawn in two halves split where the fill ends.
    ///
    /// Over the fill the text inverts against it (white + difference), which
    /// reads on any fill colour. Over the empty track that same trick blends
    /// with whatever sits behind the translucent track — on a tinted player
    /// background it turned a low-contrast grey — so that half is drawn in
    /// plain `.primary` instead. While dragging, the label floats on its own
    /// capsule, so the whole thing inverts.
    private var valueLabel: some View {
        let covered = isDragging ? labelWidth : min(labelWidth, max(0, calculateProgressWidth() - offsetForValue))
        return ZStack {
            valueText
                .foregroundStyle(.primary)
                .mask(alignment: .trailing) {
                    Rectangle().frame(width: max(0, labelWidth - covered))
                }
            valueText
                .foregroundStyle(.white)
                .mask(alignment: .leading) {
                    Rectangle().frame(width: covered)
                }
                .blendMode(.difference)
        }
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: delayDrag ? 16 : 0)
            .onChanged(handleDragChanged)
            .onEnded(handleDragEnded)
    }
    
    private func handleDragChanged(_ gesture: DragGesture.Value) {
        applyDrag(translation: gesture.translation.width)
    }

    private func applyDrag(translation: CGFloat) {
        onEditingChanged(true)
        calculateNewValue(translation: translation)
    }
    
    private func handleDragEnded(_ gesture: DragGesture.Value) {
#if targetEnvironment(macCatalyst) || os(macOS)
        if gesture.translation.width == 0.0, width > 0 {
            value = math.value(atFraction: gesture.location.x / width)
        }
#endif
        onEditingChanged(false)
        startingValue = nil
    }
    
    private func calculateNewValue(translation: CGFloat) {
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
    
    /// Where the label starts along the track: `ValueLabelPlacement`'s
    /// rule, from the measured width, for the share of it over the fill.
    private var offsetForValue: Double {
        min(max(0, calculateProgressWidth() - 28), max(0, width - 28))
    }
}

/// The fill: its one subview as wide as `fraction` of the bounds, at the
/// leading edge, its full height.
private struct LeadingFraction: Layout {
    var fraction: Double

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let width = fraction.isFinite ? bounds.width * min(max(fraction, 0), 1) : 0
        for subview in subviews {
            subview.place(at: bounds.origin, anchor: .topLeading, proposal: ProposedViewSize(width: width, height: bounds.height))
        }
    }
}

/// The value label along the track: its leading edge `inset` points short
/// of the fill's end, kept within the track.
private struct ValueLabelPlacement: Layout {
    var fraction: Double
    var inset: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let label = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: proposal.width ?? label.width, height: label.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        guard let label = subviews.first else { return }
        let fill = fraction.isFinite ? bounds.width * min(max(fraction, 0), 1) : 0
        let x = min(max(0, fill - inset), max(0, bounds.width - inset))
        label.place(at: CGPoint(x: bounds.minX + x, y: bounds.midY), anchor: .leading, proposal: .unspecified)
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
/// The slider's drag on touch-down, as a UIKit recognizer: a zero-duration
/// long press, which begins the moment a finger lands. A pan only begins
/// after ~10pt of travel, and until then the navigation stack's full-screen
/// back swipe is free to take the touch. Reports the horizontal distance
/// moved since the touch landed.
///
/// With `onLongPress`, the edit waits for the finger to move: held still
/// for half a second, the touch is the long press instead, and never an
/// edit (the volume sliders unmute when an edit starts).
@available(iOS 18.0, *)
private struct TouchDownDrag: UIGestureRecognizerRepresentable {
    var isEnabled: Bool
    var onChanged: (CGFloat) -> Void
    var onEnded: () -> Void
    var onLongPress: (() -> Void)?

    /// How far a held finger may drift before the touch is a drag.
    private static let slop: CGFloat = 4

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let press = UILongPressGestureRecognizer()
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        press.delegate = context.coordinator
        return press
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let touch = context.coordinator
        switch recognizer.state {
        case .began:
            touch.startX = recognizer.location(in: recognizer.view).x
            touch.didLongPress = false
            touch.longPress?.cancel()
            if let onLongPress {
                touch.isDragging = false
                touch.longPress = Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(500))
                    guard !Task.isCancelled, !touch.isDragging else { return }
                    touch.didLongPress = true
                    onLongPress()
                }
            } else {
                touch.isDragging = true
                onChanged(0)
            }
        case .changed:
            let x = recognizer.location(in: recognizer.view).x
            if !touch.isDragging {
                guard !touch.didLongPress, abs(x - touch.startX) > Self.slop else { return }
                touch.isDragging = true
                touch.longPress?.cancel()
                // Measured from here, so the slop it took to tell a drag
                // from a press doesn't jump the level.
                touch.startX = x
            }
            onChanged(x - touch.startX)
        case .ended, .cancelled, .failed:
            touch.longPress?.cancel()
            touch.longPress = nil
            if touch.isDragging {
                touch.isDragging = false
                onEnded()
            }
        default:
            break
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var startX: CGFloat = 0
        /// The touch has started an edit.
        var isDragging = false
        /// The touch was held still into a long press.
        var didLongPress = false
        var longPress: Task<Void, Never>?

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldBeRequiredToFailBy other: UIGestureRecognizer) -> Bool {
            isContentPopGesture(other, above: gestureRecognizer.view)
        }

        /// Whether `other` is the full-screen back swipe of any navigation
        /// controller above the slider — a collapsed NavigationSplitView nests
        /// them, and the swipe belongs to the outer one.
        private func isContentPopGesture(_ other: UIGestureRecognizer, above view: UIView?) -> Bool {
            guard #available(iOS 26.0, *) else { return false }
            var responder: UIResponder? = view
            while let current = responder {
                if let navigation = current as? UINavigationController,
                   other === navigation.interactiveContentPopGestureRecognizer {
                    return true
                }
                responder = current.next
            }
            return false
        }
    }
}

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
