#if targetEnvironment(macCatalyst)
import UIKit

// MARK: - Window Size Persistence

/// Where a window's frame is kept between launches: the main window's, and
/// the Settings window's (`SettingsWindow`).
struct WindowFrameStore {
    let key: String

    static let main = WindowFrameStore(key: "DefaultSceneLatestSystemFrame")
    static let settings = WindowFrameStore(key: "SettingsWindowSystemFrame")

    var savedFrame: CGRect? {
        guard let dict = UserDefaults.standard.dictionary(forKey: key),
              let x = dict["x"] as? CGFloat,
              let y = dict["y"] as? CGFloat,
              let w = dict["w"] as? CGFloat,
              let h = dict["h"] as? CGFloat else { return nil }
        return CGRect(x: x, y: y, width: w, height: h)
    }

    func save(_ frame: CGRect) {
        UserDefaults.standard.set(["x": frame.origin.x, "y": frame.origin.y, "w": frame.width, "h": frame.height], forKey: key)
    }
}

final class WindowSizeObserver: NSObject {
    @objc private var observedScene: UIWindowScene?
    private var observation: NSKeyValueObservation?
    private var debounceWork: DispatchWorkItem?
    private let store: WindowFrameStore
    /// The last frame seen, for a quit within the second a save waits:
    /// written then, else a window resized just before ⌘Q came back at its
    /// old size.
    private var latestFrame: CGRect?
    private var terminationObserver: NSObjectProtocol?

    init(windowScene: UIWindowScene, store: WindowFrameStore) {
        self.observedScene = windowScene
        self.store = store
        super.init()
        terminationObserver = NotificationCenter.default.addObserver(forName: UIApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            self?.saveNow()
        }
        observation = observe(\.observedScene?.effectiveGeometry, options: [.new]) { [weak self] _, change in
            guard let self,
                  let frame = change.newValue??.systemFrame,
                  frame.size != .zero else { return }
            self.latestFrame = frame
            self.debounceWork?.cancel()
            let work = DispatchWorkItem {
                store.save(frame)
            }
            self.debounceWork = work
            // Once the window has been still a second: a write of any key
            // runs every view holding `@AppStorage` again, which mid-drag
            // made the resize stutter.
            DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1, execute: work)
        }
    }

    /// Writes the last frame seen at once, rather than after the pause.
    func saveNow() {
        debounceWork?.cancel()
        if let latestFrame {
            store.save(latestFrame)
        }
    }

    deinit {
        debounceWork?.cancel()
        if let terminationObserver {
            NotificationCenter.default.removeObserver(terminationObserver)
        }
    }
}
#endif
