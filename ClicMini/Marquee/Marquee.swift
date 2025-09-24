import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var duration: Double = 6.0
    var delay: Double = 2.0

    @State private var textSize: CGSize = .zero
    @State private var animate: Bool = false
    
    init(_ text: String) {
        self.text = text
    }
    
    var body: some View {
        ViewThatFits {
            Text(text)
            marqueeView
        }
    }
    
    var marqueeView: some View {
        GeometryReader { geo in
            let containerWidth = geo.size.width
            ZStack {
                HStack(spacing: 30) {
                    Text(text)
                        .font(font)
                        .background(
                            GeometryReader { textGeo in
                                Color.clear
                                    .onAppear {
                                        textSize = textGeo.size
                                        animate = true
                                    }
                            }
                        )
                        .fixedSize()
                    
                    Text(text)
                        .font(font)
                        .fixedSize()
                }
                .offset(x: animate ? -textSize.width - 30 : 0)
                .animation(
                    animate
                    ? Animation.easeInOut(duration: duration)
                        .delay(delay)
                        .repeatForever(autoreverses: false)
                    : nil,
                    value: animate
                )
            }
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
        }
        .frame(height: 20) // Customize for your UI
        .mask(LinearGradient(stops: [.init(color: .black, location: 0.0),
                                     .init(color: .black, location: 0.05),
                                     .init(color: .black, location: 0.95),
                                     .init(color: .clear, location: 1.0)], startPoint: .leading, endPoint: .trailing))
    }
}
