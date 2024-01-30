//import CoreHaptics
//import UIKit
//
//@MainActor
//public class HapticManager {
//  public static let shared: HapticManager = .init()
//
//  public enum HapticType {
//    case buttonPress
//    case selection
//  }
//
//  private let selectionGenerator = UISelectionFeedbackGenerator()
//  private let impactGenerator = UIImpactFeedbackGenerator(style: .medium)
//  private let notificationGenerator = UINotificationFeedbackGenerator()
//
//  private init() {
//    #if !os(visionOS)
//    selectionGenerator.prepare()
//    impactGenerator.prepare()
//    #endif
//  }
//
//  @MainActor
//  public func fireHaptic(_ type: HapticType) {
//    guard supportsHaptics else { return }
//
//    switch type {
//    case .buttonPress:
//        impactGenerator.impactOccurred()
//    case .selection:
//        selectionGenerator.selectionChanged()
//    }
//  }
//
//  public var supportsHaptics: Bool {
//    CHHapticEngine.capabilitiesForHardware().supportsHaptics
//  }
//}
