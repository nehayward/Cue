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

    init(windowScene: UIWindowScene, store: WindowFrameStore) {
        self.observedScene = windowScene
        super.init()
        observation = observe(\.observedScene?.effectiveGeometry, options: [.new]) { [weak self] _, change in
            guard let self,
                  let frame = change.newValue??.systemFrame,
                  frame.size != .zero else { return }
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

    deinit {
        debounceWork?.cancel()
    }
}
#endif
