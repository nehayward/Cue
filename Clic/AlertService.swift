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
        alert.isShowing = false
        alert.text = text
        alert.isShowing = true
        alert.content = nil
        alert.subtitle = ""
        alert.imageName = ""

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(3))
            try Task.checkCancellation()
            alert.isShowing = false
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
        }
    }
    
    @MainActor
    func showAlert(with text: String, imageName: String, delay: Duration = .seconds(3)) {
        alertTask?.cancel()
        alert.content = nil
        alert.subtitle = ""
        alert.text = text
        alert.imageName = imageName
        alert.isShowing = true

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: delay)
            try Task.checkCancellation()
            alert.isShowing = false
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.imageName = nil
        }
    }

    func showAlertContent(with content: PlayableContent, subtitle: LocalizedStringKey, symbolName: String = "") {
        alertTask?.cancel()
        alert.content = nil
        alert.text = content.title
        alert.subtitle = subtitle
        alert.content = content
        alert.imageName = symbolName

        alertTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .milliseconds(200))
            alert.isShowing = true
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(4))
            try Task.checkCancellation()
            alert.isShowing = false
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.content = nil
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
    var handleTap: (() -> Void)? = { print("Hello") }

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
