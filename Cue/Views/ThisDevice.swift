import SwiftUI
import UIKit

/// This device as Cue names and draws it where playback can go: This Mac
/// and a laptop on the Mac, else the iPad or the iPhone. `UIDevice.name`
/// reads "iPad" in a Catalyst app, so the Move prompt offered to move the
/// queue "to iPad" from a Mac.
enum ThisDevice {
    static var name: String {
#if os(visionOS)
        String(localized: "This Device")
#elseif targetEnvironment(macCatalyst)
        String(localized: "This Mac")
#else
        UIDevice.current.userInterfaceIdiom == .pad ? String(localized: "This iPad") : String(localized: "This iPhone")
#endif
    }

    static var symbol: String {
#if os(visionOS)
        "visionpro"
#elseif targetEnvironment(macCatalyst)
        "laptopcomputer"
#else
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
#endif
    }
}
