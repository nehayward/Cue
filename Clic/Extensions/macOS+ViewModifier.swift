import SwiftUI

extension View {
    @ViewBuilder
    func customizeWindowSizeForMacOS15() -> some View {
#if targetEnvironment(macCatalyst)
        if #available(iOS 18, *) {
            frame(width: 800, height: 1000)
        } else {
            self
        }
#else
        self
#endif
    }
}
