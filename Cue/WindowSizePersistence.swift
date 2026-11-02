#if targetEnvironment(macCatalyst)
import UIKit

// MARK: - Window Size Persistence

enum WindowFrameStore {
    private static let key = "DefaultSceneLatestSystemFrame"

    static var savedFrame: CGRect? {
        get {
            guard let dict = UserDefaults.standard.dictionary(forKey: key),
                  let x = dict["x"] as? CGFloat,
                  let y = dict["y"] as? CGFloat,
                  let w = dict["w"] as? CGFloat,
                  let h = dict["h"] as? CGFloat else { return nil }
            return CGRect(x: x, y: y, width: w, height: h)
        }
        set {
            if let r = newValue {
                UserDefaults.standard.set(["x": r.origin.x, "y": r.origin.y, "w": r.width, "h": r.height], forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
    }
}

final class WindowSizeObserver: NSObject {
    @objc private var observedScene: UIWindowScene?
    private var observation: NSKeyValueObservation?
    private var debounceWork: DispatchWorkItem?

    init(windowScene: UIWindowScene) {
        self.observedScene = windowScene
        super.init()
        observation = observe(\.observedScene?.effectiveGeometry, options: [.new]) { [weak self] _, change in
            guard let self,
                  let frame = change.newValue??.systemFrame,
                  frame.size != .zero else { return }
            self.debounceWork?.cancel()
            let work = DispatchWorkItem {
                WindowFrameStore.savedFrame = frame
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
