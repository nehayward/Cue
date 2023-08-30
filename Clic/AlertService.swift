import Observation

@Observable
public final class AlertService {
    var alert = Alert()

    func showAlert(with text: String) {
        alert.text = text
        alert.isShowing = true
        Task {
            try await Task.sleep(for: .seconds(3))
            alert.text = ""
            alert.isShowing = false
        }
    }
}

@Observable
public final class Alert {
    var isShowing: Bool = false
    var text: String = ""
}
