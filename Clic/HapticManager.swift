import CoreHaptics
import UIKit

@MainActor
public class HapticManager {
  public static let shared: HapticManager = .init()

  #if os(visionOS)
  public enum FeedbackType: Int {
    case success, warning, error
  }
  #endif

  public enum HapticType {
    case buttonPress
    case dataRefresh(intensity: CGFloat)
    #if os(visionOS)
    case notification(_ type: FeedbackType)
    #else
    case notification(_ type: UINotificationFeedbackGenerator.FeedbackType)
    #endif
    case selection
  }

  #if !os(visionOS)
  private let selectionGenerator = UISelectionFeedbackGenerator()
  private let impactGenerator = UIImpactFeedbackGenerator(style: .heavy)
  private let notificationGenerator = UINotificationFeedbackGenerator()
  #endif

  private init() {
    #if !os(visionOS)
    selectionGenerator.prepare()
    impactGenerator.prepare()
    #endif
  }

  @MainActor
  public func fireHaptic(_ type: HapticType) {
    #if !os(visionOS)
    guard supportsHaptics else { return }

    switch type {
    case .buttonPress:
        impactGenerator.impactOccurred()
    case let .dataRefresh(intensity):
        impactGenerator.impactOccurred(intensity: intensity)
    case let .notification(type):
        notificationGenerator.notificationOccurred(type)
    case .selection:
        selectionGenerator.selectionChanged()
    }
    #endif
  }

  public var supportsHaptics: Bool {
    CHHapticEngine.capabilitiesForHardware().supportsHaptics
  }
}
