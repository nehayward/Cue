extension Task where Failure == Never {
    /// The task's value, or nil once `limit` has passed, whichever comes
    /// first. The task carries on either way, so this suits work that won't
    /// stop when cancelled (an AVFoundation load, a request already sent):
    /// a task group would wait for it to end before returning.
    func value(within limit: Duration) async -> Success? {
        let (answers, answer) = AsyncStream.makeStream(of: Success?.self)
        let waiting = Task<Void, Never> { answer.yield(await value) }
        let timer = Task<Void, Never> {
            try? await Task<Never, Never>.sleep(for: limit)
            answer.yield(nil)
        }
        defer {
            waiting.cancel()
            timer.cancel()
            answer.finish()
        }
        for await first in answers {
            return first
        }
        return nil
    }
}
