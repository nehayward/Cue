import SwiftUI

extension View {
    @ViewBuilder
    func customizeWindowSizeForMacOS15() -> some View {
#if targetEnvironment(macCatalyst)
        if #available(iOS 26, *) {
            self
        } else if #available(iOS 18, *) {
            frame(width: 800, height: 1000)
        } else {
            self
        }
#else
        self
#endif
    }
    
    @ViewBuilder
    func customizeWindowSizeForMacOS15(size: CGSize) -> some View {
#if targetEnvironment(macCatalyst)
        if #available(iOS 18, *) {
            frame(width: size.width, height: size.height)
        } else {
            self
        }
#else
        self
#endif
    }
    
    @ViewBuilder
    func presentationSizingiOS18() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.page)
        } else {
            self
        }
    }

    @ViewBuilder
    func presentationSizingFitted() -> some View {
        if #available(iOS 18, *) {
            presentationSizing(.fitted)
        } else {
            self
        }
    }
}
