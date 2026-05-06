import SwiftUI
import AppIntents

@available(tvOS, unavailable)
public struct VibeNumberSlider<Content: View>: View {
    @Binding var value: Double
    
    @ViewBuilder var button: (Int) -> Content
    
    private let totalRange: ClosedRange<Double> = 0...100
    private let step: Double
    private let visibleCount: Int
    
    var visibleRange: [Double] {
        let currentIndex = Int(round(value / step))
        let offset = visibleCount / 2
        let maxIndex = Int(totalRange.upperBound / step) - (visibleCount - 1)
        let start = max(0, min(currentIndex - offset, maxIndex))
        return (0..<visibleCount).map { Double((start + $0) * Int(step)) }
    }
    
    // Primary initializer with configurable visible count and step
    public init(value: Binding<Double>, visibleCount: Int = 3, step: Double = 5, @ViewBuilder button: @escaping (Int) -> Content) {
        self._value = value
        self.visibleCount = visibleCount
        self.step = step
        self.button = button
    }
    
    // Legacy initializer for backward compatibility
    public init(value: Binding<Double>, @ViewBuilder button: @escaping (Int) -> Content) {
        self._value = value
        self.visibleCount = 3
        self.step = 5
        self.button = button
    }
    
    public var body: some View {
        HStack(spacing: 5) {
            ForEach(visibleRange, id: \.self) { number in
                ZStack {
                    Text(isSelected(number) ? Int(value) : Int(number), format: .number)
                        .contentTransition(.numericText(value: number))
                        .font(.caption)
                        .bold(isSelected(number))
                        .monospacedDigit()
                        .scaleEffect(isSelected(number) ? 1.2 : 1)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background {
                            Circle()
                                .inset(by: 1)
                                .stroke(.white.secondary, lineWidth: 2)
                                .opacity(isSelected(number) ? 1 : 0)
                        }
                    
                    button(Int(number))
                        .buttonStyle(.bordered)
                        .buttonBorderShape(.circle)
                        .tint(.clear)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    @Previewable @State var sliderValue: Double = 36

    VStack(spacing: 20) {
        VStack {
            Text("3 Visible, Step 5 (Default)")
                .font(.caption)
            VibeNumberSlider(value: $sliderValue) { number in
                Button {
                    sliderValue = Double(number)
                } label: {
                    Text(number, format: .number)
                        .opacity(0.01)
                }
            }
            .frame(width: 300, height: 30)
        }
        
        VStack {
            Text("5 Visible, Step 5")
                .font(.caption)
            VibeNumberSlider(value: $sliderValue, visibleCount: 5) { number in
                Button {
                    sliderValue = Double(number)
                } label: {
                    Text(number, format: .number)
                        .opacity(0.01)
                }
            }
            .frame(width: 300, height: 30)
        }
        
        VStack {
            Text("3 Visible, Step 10")
                .font(.caption)
            VibeNumberSlider(value: $sliderValue, step: 10) { number in
                Button {
                    sliderValue = Double(number)
                } label: {
                    Text(number, format: .number)
                        .opacity(0.01)
                }
            }
            .frame(width: 300, height: 30)
        }
    }
}
