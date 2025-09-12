import SwiftUI
import AppIntents

@available(tvOS, unavailable)
public struct VibeNumberSlider<Content: View>: View {
    @Binding var value: Double
    
    @ViewBuilder var button: (Int) -> Content
    
    private let totalRange: ClosedRange<Double> = 0...100
    private let step: Double = 5

    @State private var isDragging = false
    @Namespace private var animation
    
    var visibleRange: [Double] {
        let currentIndex = Int(round(value / step))
        let start = max(0, min(currentIndex - 2, 20)) // 20 is the max index (100 / 5)
        return (0..<5).map { Double((start + $0) * 5) }
    }
    
    public init(value: Binding<Double>, @ViewBuilder button: @escaping (Int) -> Content) {
        self._value = value
        self.button = button
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            ForEach(visibleRange, id: \.self) { number in
                ZStack {
                    Text(isSelected(number) ? Int(value) : Int(number), format: .number)
                        .opacity(0)
                        .padding()
                        .background(.thickMaterial, in: .circle)
                        .frame(width: 38, height: 38)
                        .shadow(radius: 1)
                        .scaleEffect(isSelected(number) ? 1.2 : 0)

                    Text(isSelected(number) ? Int(value) : Int(number), format: .number)
                        .contentTransition(.numericText(value: number))
                        .font(.caption)
                        .bold(isSelected(number))
                        .monospacedDigit()
                        .scaleEffect(isSelected(number) ? 1.2 : 1)
                    
                    button(Int(number))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(.clear)
                }
                .frame(maxWidth: .infinity)
                .geometryGroup()
                .animation(.interactiveSpring, value: number)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(
            Capsule()
                .fill(.quaternary)
                .opacity(0.7)
        )
        .animation(.interactiveSpring, value: value)
        .geometryGroup()
        .gesture(
            DragGesture()
                .onChanged { gesture in
                    isDragging = true
//                    value = valueFrom(dragLocation: gesture.location.x, in: UIScreen.main.bounds.width)
                }
                .onEnded { _ in
                    isDragging = false
                }
        )
    }
    
    private func valueFrom(dragLocation: CGFloat, in width: CGFloat) -> Double {
        let percentage = max(0, min(1, dragLocation / width))
        let rawValue = Double(percentage) * 100
        return round(rawValue / step) * step // Round to nearest step
    }
    
    private func isSelected(_ number: Double) -> Bool {
        return abs(number - value) < step / 2
    }
}

@available(tvOS, unavailable)
#Preview {
    @Previewable @State var sliderValue: Double = 50

    VStack {
        VibeNumberSlider(value: $sliderValue) { number in
            Button {
                sliderValue = Double(number)
            } label: {
                Text(number, format: .number)
                    .opacity(0.01)
            }
        }
        
        VibeNumberSlider(value: $sliderValue) { number in
            Button {
                sliderValue = Double(number)
            } label: {
                Text(number, format: .number)
                    .opacity(0.01)
            }
        }
        .frame(width: 200)
    }
}
