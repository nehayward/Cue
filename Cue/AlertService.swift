import Observation
import Foundation
import SwiftUI
import SonosKit

@Observable
public final class AlertService: @unchecked Sendable {
    public static var shared = AlertService()
    var alert = Alert()
    private var alertTask: Task<Void, Error>?

    @MainActor
    func showAlert(with text: String) {
        alertTask?.cancel()
        alert.handleTap = nil
        alert.isLoading = false
        alert.progress = nil
        alert.isShowing = false
        alert.text = text
        showAlert(show: false)
        alert.content = nil
        alert.subtitle = ""
        alert.imageName = ""

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(3))
            try Task.checkCancellation()
            showAlert(show: false)
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
        }
    }
    
    @MainActor
    func showAlert(with text: String, imageName: String, delay: Duration = .seconds(3)) {
        alertTask?.cancel()
        alert.handleTap = nil
        alert.isLoading = false
        alert.progress = nil
        alert.content = nil
        alert.subtitle = ""
        alert.text = text
        alert.imageName = imageName
        showAlert(show: true)

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            showAlert(show: false)
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.imageName = nil
        }
    }
    
    @MainActor
    func showAlert(with text: String, imageName: String, action: @escaping () -> Void) {
        alertTask?.cancel()
        alert.isLoading = false
        alert.progress = nil
        alert.content = nil
        alert.subtitle = ""
        alert.text = text
        alert.imageName = imageName
        showAlert(show: true)
        alert.handleTap = { [weak self] in
            action()
            self?.showAlert(show: false)
        }
    }

    /// Shows a tappable banner with its own subtitle — "Tap for Cue Super",
    /// say — that runs `action` when tapped, and auto-dismisses after `delay`.
    @MainActor
    func showActionAlert(with text: String, subtitle: LocalizedStringKey, imageName: String, delay: Duration = .seconds(5), action: @escaping () -> Void) {
        alertTask?.cancel()
        alert.isLoading = false
        alert.content = nil
        alert.subtitle = subtitle
        alert.text = text
        alert.imageName = imageName
        showAlert(show: true)
        alert.handleTap = { [weak self] in
            action()
            self?.showAlert(show: false)
        }

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            showAlert(show: false)
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.subtitle = ""
            alert.imageName = nil
        }
    }

    /// Shows a tappable "Undo" banner that runs `action` when tapped, and auto-dismisses after a short window.
    @MainActor
    func showUndoAlert(with text: String, delay: Duration = .seconds(5), action: @escaping () -> Void) {
        alertTask?.cancel()
        alert.isLoading = false
        alert.progress = nil
        alert.content = nil
        alert.subtitle = "Tap to undo"
        alert.text = text
        alert.imageName = "arrow.uturn.backward"
        showAlert(show: true)
        alert.handleTap = { [weak self] in
            action()
            self?.showAlert(show: false)
        }

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            showAlert(show: false)
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.subtitle = ""
            alert.imageName = nil
        }
    }

    func showAlertContent(with content: PlayableContent, subtitle: LocalizedStringKey, symbolName: String = "") {
        alertTask?.cancel()
        // Clear any previous tap handler so a stale deep-link (or none) can't fire on this toast;
        // callers that want tap-through set `handleTap` right after calling this.
        alert.handleTap = nil
        alert.isLoading = false
        alert.progress = nil
        alert.text = content.title
        alert.subtitle = subtitle
        withAnimation {
            alert.content = content
        }
        alert.imageName = symbolName

        alertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .milliseconds(200))
            showAlert(show: true)
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(4))
            try Task.checkCancellation()
            showAlert(show: false)
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.content = nil
        }
    }
    
    /// Shows a persistent banner with a loading spinner while `content` is
    /// being sent to the speaker. Never auto-dismisses — the caller replaces
    /// it (e.g. with the "Playing" confirmation or an error alert) when the
    /// operation finishes.
    @MainActor
    func showLoadingContent(with content: PlayableContent, subtitle: LocalizedStringKey = "Loading…") {
        alertTask?.cancel()
        alert.handleTap = nil
        alert.text = content.title
        alert.subtitle = subtitle
        alert.imageName = nil
        alert.isLoading = true
        alert.progress = nil
        withAnimation {
            alert.content = content
        }
        showAlert(show: true)
    }

    /// The loading banner with how far a long queue has got: a line of
    /// text ("Adding album 3 of 12") and a bar under it. Call it as each
    /// item lands; like `showLoadingContent`, it stays up until the caller
    /// replaces it.
    @MainActor
    func showLoadingProgress(with content: PlayableContent, subtitle: LocalizedStringKey, fraction: Double) {
        if !alert.isLoading || alert.content != content || !alert.isShowing {
            showLoadingContent(with: content, subtitle: subtitle)
        }
        alert.subtitle = subtitle
        alert.progress = min(max(fraction, 0), 1)
    }

    private func showAlert(show: Bool) {
        withAnimation { [weak self] in
            guard let self else { return }
            alert.isShowing = show
        }
    }
}

@Observable
public final class Alert: Equatable {
    var isShowing: Bool = false
    var text: String = ""
    var subtitle: LocalizedStringKey = ""
    var imageName: String?
    var content: PlayableContent?
    /// Shows a spinner in place of the trailing symbol while content is being
    /// queued to the speaker.
    var isLoading: Bool = false
    /// How far through a long operation, 0–1, drawn as a bar under the
    /// text; nil for none.
    var progress: Double?
    var handleTap: (() -> Void)? = nil

    public static func == (lhs: Alert, rhs: Alert) -> Bool {
        lhs.isShowing != rhs.isShowing
    }
}

extension View {
    @ViewBuilder
    func withAlert(enabled: Bool = true) -> some View {
        if enabled {
            overlay(alignment: .top) {
                AlertView()
            }
        } else {
            self
        }
    }
}
