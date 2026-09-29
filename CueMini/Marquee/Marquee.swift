import SwiftUI
import AppKit

/// A single line of text that scrolls when it doesn't fit, resting at the start
/// between passes.
///
/// The motion is a Core Animation keyframe animation, so the render server runs
/// the whole cycle — rest, scroll, rest — out of process. The app does no
/// per-frame work at all, not even SwiftUI's own animation interpolation, and
/// the scroll holds its frame rate while the main thread is busy.
///
/// The text itself is still SwiftUI: it is hosted inside the animated layer and
/// handed this view's environment, so callers keep styling it with `.font`,
/// `.bold()`, `.fontDesign` and `.foregroundStyle` like any other view.
struct MarqueeText: View {
    let text: String
    /// Points per second.
    var speed: CGFloat = 32.5
    var spacing: CGFloat = 20
    var pause: TimeInterval = 1.5

    // No scene-phase gate here, unlike the phone: a menu bar extra's scene
    // phase doesn't track whether its menu is open. The animation is removed
    // when the view leaves its window, which is the signal that counts.

    @State private var textWidth: CGFloat = 0

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            Text(text)
                .lineLimit(1)
            // The hidden text gives the row its height and SwiftUI's own
            // styling; the layer drawn over it does the moving.
            Text(text)
                .lineLimit(1)
                .hidden()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(alignment: .leading) {
                    Text(text)
                        .fixedSize()
                        .hidden()
                        .onGeometryChange(for: CGFloat.self) { proxy in
                            proxy.size.width
                        } action: { width in
                            textWidth = width
                        }
                }
                .overlay {
                    MarqueeLayerView(
                        text: text,
                        textWidth: textWidth,
                        speed: speed,
                        spacing: spacing,
                        pause: pause
                    )
                }
        }
    }
}

private struct MarqueeLayerView: NSViewRepresentable {
    let text: String
    let textWidth: CGFloat
    let speed: CGFloat
    let spacing: CGFloat
    let pause: TimeInterval

    func makeNSView(context: Context) -> MarqueeNSView {
        MarqueeNSView()
    }

    func updateNSView(_ view: MarqueeNSView, context: Context) {
        view.update(
            content: AnyView(
                HStack(spacing: spacing) {
                    Text(text)
                        .fixedSize()
                    Text(text)
                        .fixedSize()
                        .accessibilityHidden(true)
                }
                .lineLimit(1)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                // Hosted content doesn't inherit the environment on its own;
                // without this the caller's font, weight and colour are lost.
                .environment(\.self, context.environment)
            ),
            configuration: .init(
                text: text,
                // 0 until the text has been measured: nothing to scroll yet.
                distance: textWidth > 0 ? textWidth + spacing : 0,
                speed: speed,
                pause: pause
            )
        )
    }
}

private final class MarqueeNSView: NSView {
    struct Configuration: Equatable {
        var text: String
        var distance: CGFloat
        var speed: CGFloat
        var pause: TimeInterval
    }

    private static let scrollKey = "marquee.scroll"
    private static let fadeKey = "marquee.fade"

    /// Leading edge hard while resting, faded while scrolling.
    private static let restingColors = [NSColor.black.cgColor, NSColor.black.cgColor,
                                        NSColor.black.cgColor, NSColor.clear.cgColor]
    private static let scrollingColors = [NSColor.clear.cgColor, NSColor.black.cgColor,
                                          NSColor.black.cgColor, NSColor.clear.cgColor]

    private let host = NSHostingView(rootView: AnyView(EmptyView()))
    private let fade = CAGradientLayer()
    private var configuration: Configuration?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true

        host.sizingOptions = []
        host.wantsLayer = true
        addSubview(host)

        fade.startPoint = CGPoint(x: 0, y: 0.5)
        fade.endPoint = CGPoint(x: 1, y: 0.5)
        fade.locations = [0, 0.04, 0.95, 1]
        fade.colors = Self.restingColors
        layer?.mask = fade
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// Clicks and hover belong to the SwiftUI views around the title.
    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    func update(content: AnyView, configuration: Configuration) {
        host.rootView = content
        guard configuration != self.configuration else { return }
        self.configuration = configuration
        needsLayout = true
        restart()
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let width = max((configuration?.distance ?? 0) * 2, bounds.width)
        host.frame = CGRect(x: 0, y: 0, width: width, height: bounds.height)
        fade.frame = bounds
        CATransaction.commit()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        restart()
    }

    /// Replaces the running cycle with a fresh one that begins at rest.
    private func restart() {
        guard let scrolling = host.layer else { return }
        scrolling.removeAnimation(forKey: Self.scrollKey)
        fade.removeAnimation(forKey: Self.fadeKey)

        guard window != nil,
              let configuration,
              configuration.distance > 0,
              configuration.speed > 0
        else { return }

        let scrollDuration = TimeInterval(configuration.distance / configuration.speed)
        let cycle = configuration.pause + scrollDuration
        let restEnds = NSNumber(value: configuration.pause / cycle)
        let begin = CACurrentMediaTime()

        // Rest at 0, then slide exactly one copy's width plus spacing. The
        // second copy now sits where the first began, so the jump back to 0 as
        // the animation repeats can't be seen.
        let scroll = CAKeyframeAnimation(keyPath: "transform.translation.x")
        scroll.values = [0, 0, -configuration.distance]
        scroll.keyTimes = [0, restEnds, 1]
        scroll.timingFunctions = [CAMediaTimingFunction(name: .linear),
                                  CAMediaTimingFunction(name: .linear)]
        scroll.duration = cycle
        scroll.repeatCount = .infinity
        scroll.beginTime = begin
        scroll.isRemovedOnCompletion = false
        scrolling.add(scroll, forKey: Self.scrollKey)

        let fadeEdge = CAKeyframeAnimation(keyPath: "colors")
        fadeEdge.values = [Self.restingColors, Self.scrollingColors]
        fadeEdge.keyTimes = [0, restEnds, 1]
        fadeEdge.calculationMode = .discrete
        fadeEdge.duration = cycle
        fadeEdge.repeatCount = .infinity
        fadeEdge.beginTime = begin
        fadeEdge.isRemovedOnCompletion = false
        fade.add(fadeEdge, forKey: Self.fadeKey)
    }
}
