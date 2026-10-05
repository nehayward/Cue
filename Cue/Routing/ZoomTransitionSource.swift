import SwiftUI

/// Names the view a zoom transition grows out of.
///
/// An enum rather than a string literal at each end. `matchedTransitionSource`
/// and `.zoom(sourceID:)` have to agree exactly, and a mismatch compiles
/// perfectly happily — it just silently downgrades the zoom to a cross-fade,
/// or, if the source is missing altogether, throws "cannot morph from a view
/// that is not in the hierarchy" and kills the app. Neither failure points at
/// the typo that caused it, so the two ends are worth making derivable from one
/// declaration.
public enum ZoomTransitionSource: Hashable {
    /// The mini player in the tab bar accessory. Opens `PlayerView`.
    case miniPlayer
    /// One album's cover in a grid, by the album's id. Opens
    /// `MediaDetailView`, which grows out of the tile that was tapped.
    case album(String)
    /// The Play On button. Opens `PlayOnSheet`, which morphs out of it the
    /// way the system's AirPlay picker grows out of its button.
    case playOn
}

extension EnvironmentValues {
    /// The namespace the app's zoom transitions share, set once at the root
    /// so a grid deep in a tab and the screen its tap pushes — rendered by
    /// the navigation stack, not by the grid — name the same one. Nil in
    /// previews and anywhere else the root hasn't set it, where a tap
    /// pushes without a zoom.
    @Entry var zoomNamespace: Namespace.ID? = nil
}

extension View {
    /// Marks this view as what `source` zooms out of.
    func zoomSource(_ source: ZoomTransitionSource, in namespace: Namespace.ID) -> some View {
        matchedTransitionSource(id: source, in: namespace)
    }

    /// Presents this view by zooming out of `source`, which must be on screen
    /// at the moment the presentation begins.
    func zoomTransition(from source: ZoomTransitionSource, in namespace: Namespace.ID) -> some View {
        navigationTransition(.zoom(sourceID: source, in: namespace))
    }
}
