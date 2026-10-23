import SwiftUI

extension View {
    /// Pulses the symbol once `isActive` has held for `delay`, and stops as
    /// soon as it clears.
    ///
    /// A transport state that's only true for a moment — the speaker buffering
    /// for a beat when the app comes back, a quick seek — flashed a pulse the
    /// instant it was reported. Holding off until the wait is long enough to
    /// notice is the same rule a loading spinner follows: a real wait still
    /// shows, a blip doesn't.
    public func sustainedPulse(isActive: Bool, after delay: Duration = .milliseconds(600)) -> some View {
        modifier(SustainedPulse(isActive: isActive, delay: delay))
    }
}

private struct SustainedPulse: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    let isActive: Bool
    let delay: Duration
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            // Never while the app isn't active: the process outlives the
            // screen, and a trace showed pulses started by buffering on a
            // locked phone animating every frame for seconds.
            .symbolEffect(.pulse, isActive: isPulsing && scenePhase == .active)
            // Restarted on every change, so a cleared state cancels the wait.
            .task(id: isActive) {
                guard isActive else {
                    isPulsing = false
                    return
                }
                try? await Task.sleep(for: delay)
                guard !Task.isCancelled else { return }
                isPulsing = true
            }
    }
}
