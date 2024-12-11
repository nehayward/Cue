import SwiftUI

extension View {
    @ViewBuilder
    func searchFocusedBackport(_ binding: FocusState<Bool>.Binding)  -> some View {
        if #available(iOS 18.0, *) {
            self.searchFocused(binding)
        } else {
            self // fallback behavior for earlier versions
        }
    }
}
