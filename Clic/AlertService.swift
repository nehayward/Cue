import Observation
import Foundation

@Observable
public final class AlertService: @unchecked Sendable {
    public static var shared = AlertService()
    
    var alert = Alert()
    private let queue = DispatchQueue(label: "AlertService\(UUID().uuidString)")
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
}

@Observable
public final class Alert: Equatable {
    var isShowing: Bool = false
    var text: String = ""
    
    public static func == (lhs: Alert, rhs: Alert) -> Bool {
        lhs.isShowing != rhs.isShowing &&
        lhs.text != rhs.text
    }
}
