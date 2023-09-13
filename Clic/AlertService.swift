import Observation
import Foundation

@Observable
public final class AlertService: @unchecked Sendable {
    private(set) var alert = Alert()
    private let queue = DispatchQueue(label: "AlertService\(UUID().uuidString)")

    func showAlert(with text: String) {
        queue.sync {
            alert.text = text
            alert.isShowing = true
        }
        Task { [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .seconds(3))
            queue.sync { [weak self] in
                guard let self else { return }
                alert.text = ""
                alert.isShowing = false
            }
        }
    }
}

@Observable
public final class Alert: @unchecked Sendable {
    var isShowing: Bool = false
    var text: String = ""
}
