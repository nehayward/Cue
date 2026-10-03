import Foundation

/// A value and when it was set. A merge keeps the later one: a playlist's
/// name, notes and cover each merge this way, so renaming on one device
/// and changing the cover on another keeps both.
public struct Stamped<Value: Codable & Equatable & Sendable>: Codable, Equatable, Sendable {
    public var value: Value
    public var at: Date

    public init(_ value: Value, at date: Date) {
        self.value = value
        self.at = date
    }

    public func merged(with other: Stamped) -> Stamped {
        if at != other.at {
            return at > other.at ? self : other
        }
        // Set at the same moment on two devices: either will do, as long as
        // both pick the same one.
        return TieBreak.isGreater(other, than: self) ? other : self
    }
}
