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
    func showAlert(with text: String, imageName: String) {
        alertTask?.cancel()
        alert.isShowing = false
        alert.text = text
        alert.imageName = imageName
        alert.isShowing = true

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(3))
            try Task.checkCancellation()
            alert.isShowing = false
            try await Task.sleep(for: .milliseconds(800))
            alert.text = ""
            alert.imageName = nil
        }
    }

    func showAlertContent(with content: PlayableContent) {
        alertTask?.cancel()
        alert.content = nil
        alert.isShowing = false
        alert.text = content.title
        alert.content = content
        alert.isShowing = true

        alertTask = Task { [weak self] in
            guard let self else { return }
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(3))
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
    var imageName: String?
    var content: PlayableContent?

    public static func == (lhs: Alert, rhs: Alert) -> Bool {
        lhs.isShowing != rhs.isShowing
    }
}

extension View {
    func withAlert() -> some View {
        return overlay(alignment: .top) {
            PillView()
        }
    }
}
