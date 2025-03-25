import SwiftUI

struct MarqueeText: View {
    let text: String
    @State private var isPaused: Bool = false
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        ViewThatFits {
            Text(text)
            ScrollView(.horizontal){
                Text(text)
                    .lineLimit(1)
                    .fixedSize()
                    .marquee(speed: 0.65, spacing: 20, pauseDuration: 1.5, id: text)
            }
            .scrollDisabled(true)
            .onPreferenceChange(MarqueePausedKey.self) { isPaused in
                withAnimation {
                    self.isPaused = isPaused
                }
            }
            .mask(LinearGradient(stops: [.init(color: isPaused ? .black : .clear, location: 0.0),
                                         .init(color: .black, location: 0.04),
                                         .init(color: .black, location: 0.95),
                                         .init(color: .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
        }
    }
}

extension View {
    @ViewBuilder
    func marquee(speed: CGFloat = 1, spacing: CGFloat = 80, pauseDuration: Double = 2.0, id: String) -> some View {
        modifier(
            MarqueeViewModifier(
                speed: speed,
                spacing: spacing,
                pauseDuration: pauseDuration,
                id: id
            )
        )
    }
}

struct MarqueePausedKey: PreferenceKey {
    static var defaultValue: Bool = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = nextValue()
    }
}

fileprivate struct MarqueeViewModifier: ViewModifier {
    var speed: CGFloat
    var spacing: CGFloat
    var pauseDuration: Double
    let id: String

    @State var size: CGSize = .zero
    @State var isPaused: Bool = false
    @State private var startTime: Date? = nil
    
    init(speed: CGFloat, spacing: CGFloat, pauseDuration: Double, id: String) {
        self.speed = speed
        self.spacing = spacing
        self.pauseDuration = pauseDuration
        self.id = id
    }

    func body(content: Content) -> some View {
        TimelineView(.animation) { context in
            effect(content: content, date: context.date)
                .onChange(of: context.date) { oldValue, newValue in
                    // Only start measuring elapsed time once animation begins
                    let elapsedTime = startTime.map { context.date.timeIntervalSince($0) } ?? 0
                    let animationCycleDuration = (size.width + spacing) / (50 * speed)
                    
                    let totalCycleDuration = animationCycleDuration + pauseDuration
                    let cycleProgress = elapsedTime.truncatingRemainder(dividingBy: totalCycleDuration)
                    let shouldAnimate = cycleProgress < animationCycleDuration
                    
                    // Calculate effective time for shader, starting from 0 when animation begins
                    let effectiveTime = shouldAnimate ? cycleProgress * speed : 0
                    
                    let running = effectiveTime == 0
                    withAnimation(.snappy(duration: 0.1)) {
                        isPaused = running
                    }
                }
                .preference(key: MarqueePausedKey.self, value: isPaused)
        }
        .task(id: id) {
            startTime = nil
            try? await Task.sleep(for: .seconds(pauseDuration))
            startTime = Date()
        }
    }
    
    @ViewBuilder
    func effect(content: Content, date: Date) -> some View {
        
        // Only start measuring elapsed time once animation begins
        let elapsedTime = startTime.map { date.timeIntervalSince($0) } ?? 0
        let animationCycleDuration = (size.width + spacing) / (50 * speed)
        
        // Calculate animation phase
        let totalCycleDuration = animationCycleDuration + pauseDuration
        let cycleProgress = elapsedTime.truncatingRemainder(dividingBy: totalCycleDuration)
        let shouldAnimate = cycleProgress < animationCycleDuration
        
        // Calculate effective time for shader, starting from 0 when animation begins
        let effectiveTime = shouldAnimate ? cycleProgress * speed : 0
        
        content
            .onGeometryChange(for: CGSize.self) { proxy in
                return proxy.size
            } action: { newValue in
                size = newValue
            }
            .distortionEffect(
                ShaderLibrary.marquee(
                    .float(effectiveTime
                          ),
                    .float(size.width + spacing)
                ),
                maxSampleOffset: .zero
            )
    }
}
