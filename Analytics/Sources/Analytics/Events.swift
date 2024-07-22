import Foundation

public enum AnalyticEvents: String {
    case viewedPaywall
    case viewedManageSubscription
    case viewedSceneBuilderScreen
    case subscribed
    case createdScene
    case selectedMusicService
    case numberOfDevices

    var name: String { self.rawValue }
}
