import SwiftUI

extension Binding where Value: Equatable {
    /// Calls `action` when the value is set to what it already is.
    ///
    /// This is the only way to see a tap on the already-selected tab: SwiftUI
    /// has no reselection callback (UIKit's `tabBarController(_:didSelect:)`
    /// never got an equivalent), and it reports the tap as a set to the same
    /// value — which `onChange(of:)` ignores, by definition, and a plain
    /// binding swallows.
    func reselecting(perform action: @escaping (Value) -> Void) -> Binding<Value> {
        Binding(
            get: { wrappedValue },
            set: { newValue in
                // Return without writing: a reselection changes nothing, and
                // assigning `@State` its current value still costs an
                // invalidation and a body pass.
                guard newValue != wrappedValue else {
                    action(newValue)
                    return
                }
                wrappedValue = newValue
            }
        )
    }
}
