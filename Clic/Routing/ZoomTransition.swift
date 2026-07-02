import SwiftUI

/// Bridges a `matchedTransitionSource` at a presenting call site to the
/// centrally-built sheet content in `withSheetDestinations`. Only one sheet
/// animates at a time, so a single main-actor slot is enough. The slot is
/// keyed by `SheetDestination.id` so a stale registration never attaches to
/// an unrelated sheet presented the plain way (`sheet(to:)` or a direct
/// `presentedSheet` assignment).
@MainActor
enum SheetZoomTransition {
    struct Source {
        let sheetID: String
        let sourceID: AnyHashable
        let namespace: Namespace.ID
    }

    static var source: Source?

    static func source(for destination: SheetDestination) -> Source? {
        guard let source, source.sheetID == destination.id else { return nil }
        return source
    }
}

/// The same bridge for navigation pushes: `withAppRouter` builds destination
/// views centrally, so the pushing call site registers its source here and
/// the matching destination picks it up. Keyed by the full RouterDestination
/// value; a plain `navigate(to:)` to anything else simply doesn't match, and
/// a stale registration whose source view is offscreen falls back to the
/// standard push animation.
@MainActor
enum NavigationZoomTransition {
    struct Source {
        let destination: RouterDestination
        let sourceID: AnyHashable
        let namespace: Namespace.ID
    }

    static var source: Source?

    static func source(for destination: RouterDestination) -> Source? {
        guard let source, source.destination == destination else { return nil }
        return source
    }
}

extension Router {
    /// Present `destination` as a sheet zooming out of the view marked with
    /// `.zoomTransitionSource(id:in:)` for the same `sourceID`/`namespace`.
    /// Falls back to the standard sheet animation before iOS 18, or when the
    /// source view is offscreen.
    @MainActor
    func sheet(to destination: SheetDestination, zoomFrom sourceID: AnyHashable, in namespace: Namespace.ID) {
        SheetZoomTransition.source = .init(sheetID: destination.id, sourceID: sourceID, namespace: namespace)
        presentedSheet = destination
    }

    /// Push `destination` zooming out of the view marked with
    /// `.zoomTransitionSource(id:in:)` for the same `sourceID`/`namespace`.
    /// Falls back to the standard push before iOS 18, or when the source
    /// view is offscreen.
    @MainActor
    func navigate(to destination: RouterDestination, zoomFrom sourceID: AnyHashable, in namespace: Namespace.ID) {
        NavigationZoomTransition.source = .init(destination: destination, sourceID: sourceID, namespace: namespace)
        navigate(to: destination)
    }
}

@MainActor
extension View {
    /// Marks this view as the origin of a zoom transition. Pass `nil` for
    /// `id` or `namespace` to opt out per-content — the modifier becomes a
    /// no-op, so call sites stay conditional without an outer `if`.
    @ViewBuilder
    func zoomTransitionSource(id: AnyHashable?, in namespace: Namespace.ID?) -> some View {
        if #available(iOS 18.0, *), let id, let namespace {
            matchedTransitionSource(id: id, in: namespace)
        } else {
            self
        }
    }

    /// Applied to sheet content in `withSheetDestinations`: attaches the zoom
    /// transition when the presenting call site registered a source for this
    /// destination.
    @ViewBuilder
    func zoomTransition(for destination: SheetDestination) -> some View {
        if #available(iOS 18.0, *), let source = SheetZoomTransition.source(for: destination) {
            navigationTransition(.zoom(sourceID: source.sourceID, in: source.namespace))
        } else {
            self
        }
    }

    /// Push variant, applied to destination content in `withAppRouter`.
    @ViewBuilder
    func zoomTransition(for destination: RouterDestination) -> some View {
        if #available(iOS 18.0, *), let source = NavigationZoomTransition.source(for: destination) {
            navigationTransition(.zoom(sourceID: source.sourceID, in: source.namespace))
        } else {
            self
        }
    }
}
