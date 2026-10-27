import UIKit

/// Opens the system dictionary's page for a word over whatever is on
/// screen: a word looked up before, from a book's history. Presented from
/// the top controller, as the page expects, so its Done takes away the page
/// alone and leaves the sheet or player under it. Read Along's own lookups
/// show the page in a card instead (`BookTranscriptDefinitionCard`).
@MainActor
enum DictionaryPresenter {
    static func present(_ term: String) {
        guard let top = topController(), !(top is UIReferenceLibraryViewController) else { return }
        // A sheet on its way down can't be presented over: wait for it.
        if let coordinator = top.transitionCoordinator {
            coordinator.animate(alongsideTransition: nil) { _ in present(term) }
            return
        }
        top.present(UIReferenceLibraryViewController(term: term), animated: true)
    }

    /// The controller presented last in the active window, past any on its
    /// way down.
    private static func topController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene = scenes.first { $0.activationState == .foregroundActive } ?? scenes.first
        var top = (scene?.keyWindow ?? scene?.windows.first)?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
