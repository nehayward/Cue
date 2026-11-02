import SwiftUI

extension View {
    /// A page's column of text and controls held to a reading width and
    /// centred, as Apple's own apps keep theirs on a wide screen: stretched
    /// across an iPad or an iPhone Duo open, a book page's buttons ran most
    /// of a screen wide and its history's times sat far from their lines.
    /// An iPhone is narrower than the cap, so nothing changes there. About
    /// UIKit's readable width (672 points at the default text size).
    func readableColumn() -> some View {
        frame(maxWidth: 680)
            .frame(maxWidth: .infinity)
    }
}
