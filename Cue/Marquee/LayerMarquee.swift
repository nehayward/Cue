#if targetEnvironment(macCatalyst)
import SwiftUI
import UIKit

/// `MarqueeText` on the Mac: the same rest and scroll, with the text moved by
/// Core Animation. The window server runs the animation, so nothing in Cue
/// runs per frame, where moving it from SwiftUI (a timeline or an animated
/// offset alike) took about 6% of a core for as long as a title stayed too
/// long for the player bar, which is always on screen. One added animation a
/// cycle is all Cue does.
///
/// The text is still a SwiftUI `Text`, hosted with this view's environment,
/// so it takes the font, weight and style the caller set.
struct LayerMarquee: View {
    let text: String
    var pointsPerSecond: CGFloat
    var spacing: CGFloat
    var pauseDuration: Double

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.multilineTextAlignment) private var textAlignment

    @State private var textWidth: CGFloat = 0
    @State private var lineWidth: CGFloat = 0
    @State private var isScrolling = false

    /// Before it's measured the text is taken to fit.
    private var fits: Bool {
        textWidth <= lineWidth + 0.5
    }

    private var scrollDistance: CGFloat {
        textWidth + spacing
    }

    private var scrollDuration: Double {
        Double(scrollDistance / pointsPerSecond)
    }

    private var restingAlignment: Alignment {
        switch textAlignment {
        case .leading: .leading
        case .center: .center
        case .trailing: .trailing
        }
    }

    var body: some View {
        // The hidden copies take the offered width and one line of height,
        // and measure the text.
        Text(text)
            .lineLimit(1)
            .hidden()
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { lineWidth = $0 }
            .background {
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { textWidth = $0 }
            }
            .overlay {
                if fits, !isScrolling {
                    Text(text)
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: restingAlignment)
                } else {
                    // Clicks go to whatever holds it (the bar's title opens
                    // the player), not to the UIKit view.
                    MovingLine(text: text, spacing: spacing, distance: scrollDistance, duration: scrollDuration, isScrolling: isScrolling)
                        .allowsHitTesting(false)
                }
            }
            .clipped()
            .mask(LinearGradient(stops: [.init(color: isScrolling ? .clear : .black, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: fits ? .black : .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
            // Each cycle rests, then scrolls one full length, after which the
            // copy sits exactly where the text began, so the animation ending
            // is seamless. Keyed on the phase too, so coming back on screen
            // starts from rest, and the width, so a new Interface Size scrolls
            // the distance it now takes.
            .task(id: CycleKey(text: text, width: textWidth, isActive: scenePhase == .active, fits: fits)) {
                if isScrolling {
                    withAnimation(.snappy) {
                        isScrolling = false
                    }
                }
                guard !fits, scenePhase == .active else { return }
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(pauseDuration))
                    guard !Task.isCancelled else { return }
                    isScrolling = true
                    try? await Task.sleep(for: .seconds(scrollDuration))
                    guard !Task.isCancelled else { return }
                    isScrolling = false
                }
            }
    }

    private struct CycleKey: Equatable {
        let text: String
        let width: CGFloat
        let isActive: Bool
        let fits: Bool
    }
}

/// The text and its copy on one layer, which Core Animation moves.
private struct MovingLine: UIViewRepresentable {
    let text: String
    let spacing: CGFloat
    let distance: CGFloat
    let duration: Double
    let isScrolling: Bool

    func makeUIView(context: Context) -> MovingLineView {
        let view = MovingLineView()
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: MovingLineView, context: Context) {
        view.show(UIHostingConfiguration {
            HStack(spacing: spacing) {
                Text(text)
                Text(text)
            }
            .lineLimit(1)
            .fixedSize()
            .environment(\.self, context.environment)
        }
        .margins(.all, 0))
        view.setScrolling(isScrolling, distance: distance, duration: duration)
    }
}

private final class MovingLineView: UIView {
    private static let animationKey = "marquee"

    private var content: (UIView & UIContentView)?
    private var isScrolling = false

    func show(_ configuration: some UIContentConfiguration) {
        if let content {
            content.configuration = configuration
        } else {
            let content = configuration.makeContentView()
            addSubview(content)
            self.content = content
        }
        setNeedsLayout()
    }

    func setScrolling(_ scrolling: Bool, distance: CGFloat, duration: Double) {
        guard scrolling != isScrolling, let layer = content?.layer else { return }
        isScrolling = scrolling
        if scrolling {
            // Additive to the layer's place: leaves its model alone, so a
            // layout under way doesn't disturb it, and it ends back at rest.
            let animation = CABasicAnimation(keyPath: "transform.translation.x")
            animation.fromValue = 0
            animation.toValue = -distance
            animation.duration = duration
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            layer.add(animation, forKey: Self.animationKey)
        } else {
            layer.removeAnimation(forKey: Self.animationKey)
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let content else { return }
        let size = content.sizeThatFits(CGSize(width: CGFloat.greatestFiniteMagnitude, height: bounds.height))
        content.frame = CGRect(x: 0, y: ((bounds.height - size.height) / 2).rounded(), width: size.width, height: size.height)
    }
}
#endif
