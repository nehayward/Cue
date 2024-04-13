import Foundation

public enum AnalyticEvents: String {
    case viewedPaywall
    case viewedManageSubscription
    case viewedSceneBuilderScreen
    case subscribed
    case createdScene
    case selectedMusicService

    var name: String { self.rawValue }
}
