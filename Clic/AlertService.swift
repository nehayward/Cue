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

    /// Shows a tappable "Undo" banner that runs `action` when tapped, and auto-dismisses after a short window.
    @MainActor
    func showUndoAlert(with text: String, delay: Duration = .seconds(5), action: @escaping () -> Void) {
        alertTask?.cancel()
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
