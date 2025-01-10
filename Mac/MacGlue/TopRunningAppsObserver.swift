import AppKit

class TopRunningAppsObserver {
    private let bundleIdentifier: String
    private var handler: ((Bool) -> Void)?
    private var timer: Timer?
    
    init(bundleIdentifier: String) {
        self.bundleIdentifier = bundleIdentifier
    }
    
    func start(handler: @escaping (Bool) -> Void) {
        self.handler = handler
        startTimer()
        // Check initial state
        checkIfAppIsRunning()
    }
    
    func stop() {
        timer?.invalidate()
        timer = nil
        handler = nil
    }
    
    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(
            withTimeInterval: 0.5,
            repeats: true
        ) { [weak self] _ in
            self?.checkIfAppIsRunning()
        }
    }
    
    private func checkIfAppIsRunning() {
        let isRunning = NSWorkspace.shared.runningApplications
            .contains { $0.bundleIdentifier == bundleIdentifier }
        handler?(isRunning)
    }
}

