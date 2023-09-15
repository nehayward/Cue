import Observation
import Foundation

@Observable
public final class AlertService: @unchecked Sendable {
    var alert = Alert()
    private let queue = DispatchQueue(label: "AlertService\(UUID().uuidString)")

    @MainActor
    func showAlert(with text: String) {
        alert.text = text
        alert.isShowing = true
//        queue.sync {
//            alert.text = text
//            alert.isShowing = true
//        }
        Task { [weak self] in
            guard let self else { return }
            try await Task.sleep(for: .seconds(3))
//            queue.sync { [weak self] in
//                guard let self else { return }
                alert.isShowing = false
//            }
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
