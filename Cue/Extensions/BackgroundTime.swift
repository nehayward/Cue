import UIKit

/// Runs `work` with time asked of iOS to finish it should Cue leave the
/// foreground meanwhile, given back as `work` ends or when iOS runs out of
/// patience first: a speaker given an album, the log written, a book file
/// tried again.
///
/// `beginBackgroundTask` is still iOS's way to finish a short piece of work
/// as an app leaves the foreground, and has no async form. `BGTaskScheduler`
/// is for work later, and `BGContinuedProcessingTask` for long work the user
/// started, with the system's progress card (the downloads). Scoped as
/// `withTaskGroup` is, so the time can't be left held.
@MainActor
func withBackgroundTime<T>(named name: String, _ work: @MainActor () async throws -> T) async rethrows -> T {
    let grant = BackgroundGrant(name: name)
    defer { grant.end() }
    return try await work()
}

/// The time asked for, given back once: by the work ending, or by iOS's
/// expiration handler.
@MainActor
private final class BackgroundGrant {
    private var id = UIBackgroundTaskIdentifier.invalid

    init(name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            MainActor.assumeIsolated { self?.end() }
        }
    }

    func end() {
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
