#if os(iOS) || os(visionOS)
import SwiftUI
import UIKit

/// A pan that only ever starts sideways.
///
/// One that sets off up or down fails at once, so a list's scroll and a
/// sheet's pull to dismiss get every vertical drag as if the view weren't
/// there. Their pans wait for it to fail, the few points it takes to tell,
/// so a sideways drag is never a scroll or a dismiss as well. UIKit rather
/// than a SwiftUI drag: only a recognizer can decline to begin, where a
/// SwiftUI gesture takes the touch first and decides after.
///
/// Attach it with `sidewaysPan(isEnabled:onBegan:onChanged:onEnded:)`,
/// which falls back to a SwiftUI drag before iOS 18.
@available(iOS 18.0, visionOS 2.0, *)
public struct SidewaysPan: UIGestureRecognizerRepresentable {
    public var isEnabled: Bool
    public let onBegan: () -> Void
    /// Points moved sideways since it began.
    public let onChanged: (CGFloat) -> Void
    public let onEnded: () -> Void

    public init(
        isEnabled: Bool = true,
        onBegan: @escaping () -> Void,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) {
        self.isEnabled = isEnabled
        self.onBegan = onBegan
        self.onChanged = onChanged
        self.onEnded = onEnded
    }

    public func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator()
    }

    public func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let pan = UIPanGestureRecognizer()
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        return pan
    }

    public func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        recognizer.isEnabled = isEnabled
    }

    public func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        switch recognizer.state {
        case .began:
            // Measured from here, not from where the finger landed: the few
            // points it took to tell the direction shouldn't jump the level.
            recognizer.setTranslation(.zero, in: recognizer.view)
            onBegan()
        case .changed:
            onChanged(recognizer.translation(in: recognizer.view).x)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    public final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        public func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard let pan = recognizer as? UIPanGestureRecognizer else { return true }
            let moved = pan.translation(in: pan.view)
            let motion = moved == .zero ? pan.velocity(in: pan.view) : moved
            return abs(motion.x) > abs(motion.y)
        }

        /// The list's pan and the sheet's: any other pan the touch could
        /// start.
        public func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            other is UIPanGestureRecognizer && other !== recognizer
        }
    }
}

public extension View {
    /// A drag that only counts sideways: `SidewaysPan` where the system has
    /// it (iOS 18), and before that a SwiftUI drag that decides its way once
    /// it has gone past a dead zone, as `VibeSlider`'s `delayDrag` does.
    ///
    /// `onChanged` gets the points moved sideways since `onBegan`, so a value
    /// set from it should be relative to where the drag began, not to where
    /// the finger is: a tap never jumps it.
    @ViewBuilder
    func sidewaysPan(
        isEnabled: Bool = true,
        onBegan: @escaping () -> Void,
        onChanged: @escaping (CGFloat) -> Void,
        onEnded: @escaping () -> Void
    ) -> some View {
        if #available(iOS 18.0, visionOS 2.0, *) {
            gesture(SidewaysPan(isEnabled: isEnabled, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        } else {
            modifier(SidewaysDrag(isEnabled: isEnabled, onBegan: onBegan, onChanged: onChanged, onEnded: onEnded))
        }
    }
}

/// `SidewaysPan` before iOS 18: a SwiftUI drag that waits out a dead zone,
/// then either takes the drag (mostly sideways) or lets it go for good.
/// It can't make the list wait for it, so the dead zone is what keeps a
/// vertical drag the list's.
private struct SidewaysDrag: ViewModifier {
    let isEnabled: Bool
    let onBegan: () -> Void
    let onChanged: (CGFloat) -> Void
    let onEnded: () -> Void

    private enum Way: Equatable {
        /// Sideways, from this far across when it was decided.
        case sideways(from: CGFloat)
        case other
    }

    /// `nil` until the drag has left the dead zone.
    @State private var way: Way?
    @GestureState private var isDragging = false

    private static let deadZone: CGFloat = 16

    func body(content: Content) -> some View {
        content
            .gesture(drag, including: isEnabled ? .all : .subviews)
            .onChange(of: isDragging) { _, dragging in
                guard !dragging else { return }
                // A drag the system took away (the list claiming it, the
                // sheet closing) only resets its gesture state and never
                // calls `onEnded`: finish it here, a turn later so a normal
                // end's `onEnded` always goes first.
                Task { @MainActor in
                    guard !isDragging, way != nil else { return }
                    finish()
                }
            }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: Self.deadZone)
            .updating($isDragging) { _, state, _ in state = true }
            .onChanged { value in
                switch way {
                case nil:
                    let moved = value.translation
                    if abs(moved.width) > abs(moved.height) {
                        way = .sideways(from: moved.width)
                        onBegan()
                    } else {
                        way = .other
                    }
                case let .sideways(from)?:
                    onChanged(value.translation.width - from)
                case .other?:
                    break
                }
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        if case .sideways? = way {
            onEnded()
        }
        way = nil
    }
}
#endif
