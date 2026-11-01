import Foundation
import Observation
import UIKit

/// When a shelf widget's publisher writes, for the book shelf and Albums
/// alike: a moment after what its shelves are made of changes, the last of
/// several changes; at once as Cue leaves the foreground, as iOS may suspend
/// it before then; and a moment after it comes back, as a widget set to
/// something new in Edit Widget meanwhile tells Cue nothing.
@MainActor
final class WidgetWriteSchedule {
    /// Writes the shelves; told whether they must go now (Cue leaving).
    private let write: @MainActor (_ now: Bool) -> Void
    private var waiting: Task<Void, Never>?
    private var observers: [any NSObjectProtocol] = []

    /// Whether a write is waiting.
    var isWaiting: Bool { waiting != nil }

    init(write: @escaping @MainActor (_ now: Bool) -> Void) {
        self.write = write
    }

    /// From now on: the first write after `delay`, a write at once as Cue
    /// leaves the foreground, and one a second after it comes back, when
    /// `onActive` runs too.
    func start(firstAfter delay: Duration, onActive: @escaping @MainActor () -> Void = {}) {
        guard observers.isEmpty else { return }
        after(delay)
        let center = NotificationCenter.default
        observers = [
            center.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.now() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.after(.seconds(1))
                    onActive()
                }
            },
        ]
    }

    /// A write after `delay`, in place of any waiting.
    func after(_ delay: Duration) {
        waiting?.cancel()
        waiting = Task {
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            waiting = nil
            write(false)
        }
    }

    /// A write now, in place of any waiting.
    func now() {
        waiting?.cancel()
        waiting = nil
        write(true)
    }

    /// Runs `onChange` whenever anything `read` reads changes, from now on:
    /// `withObservationTracking`, armed again after each change. Call it
    /// once for each thing followed; each chain keeps itself going.
    func follow(_ read: @escaping @MainActor () -> Void, onChange: @escaping @MainActor () -> Void) {
        withObservationTracking {
            read()
        } onChange: {
            Task { @MainActor [weak self] in
                onChange()
                self?.follow(read, onChange: onChange)
            }
        }
    }
}
