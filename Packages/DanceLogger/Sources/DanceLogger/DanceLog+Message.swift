import Foundation

public extension DanceLog {
    /// The text of a line, written as a string literal with interpolations.
    /// Any value can be interpolated: strings and numbers write themselves
    /// in, anything else is described with `String(describing:)`.
    ///
    /// `privacy:` is accepted the way `os.Logger` spells it, so calls written
    /// for one read the same here. `.public` (and leaving it out) writes the
    /// value; `.private` writes `<private>` in its place, in the system log
    /// and the file alike — for something a bug report never needs, like a
    /// person's name.
    struct Message: ExpressibleByStringInterpolation, Sendable {
        public let text: String

        public init(stringLiteral value: String) {
            text = value
        }

        public init(stringInterpolation: StringInterpolation) {
            text = stringInterpolation.text
        }

        public struct StringInterpolation: StringInterpolationProtocol {
            fileprivate var text = ""

            public init(literalCapacity: Int, interpolationCount: Int) {
                text.reserveCapacity(literalCapacity + interpolationCount * 16)
            }

            public mutating func appendLiteral(_ literal: String) {
                text += literal
            }

            // The same four overloads as the standard library's
            // `DefaultStringInterpolation`: strings and numbers write
            // themselves straight in, and only other values go through
            // `String(describing:)`, which is several times slower.

            public mutating func appendInterpolation<Value>(_ value: Value) where Value: TextOutputStreamable, Value: CustomStringConvertible {
                value.write(to: &text)
            }

            public mutating func appendInterpolation<Value: TextOutputStreamable>(_ value: Value) {
                value.write(to: &text)
            }

            public mutating func appendInterpolation<Value: CustomStringConvertible>(_ value: Value) {
                text += value.description
            }

            public mutating func appendInterpolation<Value>(_ value: Value) {
                text += String(describing: value)
            }

            public mutating func appendInterpolation<Value>(_ value: Value, privacy: Privacy) where Value: TextOutputStreamable, Value: CustomStringConvertible {
                if privacy == .public { appendInterpolation(value) } else { appendLiteral("<private>") }
            }

            public mutating func appendInterpolation<Value: TextOutputStreamable>(_ value: Value, privacy: Privacy) {
                if privacy == .public { appendInterpolation(value) } else { appendLiteral("<private>") }
            }

            public mutating func appendInterpolation<Value: CustomStringConvertible>(_ value: Value, privacy: Privacy) {
                if privacy == .public { appendInterpolation(value) } else { appendLiteral("<private>") }
            }

            public mutating func appendInterpolation<Value>(_ value: Value, privacy: Privacy) {
                if privacy == .public { appendInterpolation(value) } else { appendLiteral("<private>") }
            }
        }
    }

    /// Whether an interpolated value is written out. See `Message`.
    enum Privacy: Sendable {
        case `public`
        case `private`
    }
}
