import Foundation

/// Where something sits in a list that several devices edit apart: a short
/// string that sorts between its neighbours. Putting a song between two
/// others writes one key and leaves every other song alone, so edits made
/// on different devices touch different keys, and their lists merge by
/// sorting.
///
/// Keys are base-62 strings with a variable-length integer head
/// (rocicorp's fractional-indexing, CC0). Adding to the end, the usual case,
/// counts up `a0`, `a1` … `az`, `b00` and stays short; only putting
/// something between two neighbours lengthens a key. Keys compare bytewise
/// (`precedes`), which is ASCII order: digits, then upper case, then lower
/// case.
public enum OrderKey {
    public enum Failure: Error, Equatable {
        /// Not a key this scheme makes.
        case invalid(String)
        /// The lower bound doesn't sort before the upper one.
        case outOfOrder(String, String)
        /// Past the largest or smallest integer a key can hold (`z` or
        /// `A` followed by 26 digits): not reachable by editing a playlist.
        case exhausted
    }

    typealias Bytes = [UInt8]

    static let digits: Bytes = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz".utf8)
    private static let zero = digits[0]
    private static let largestDigit = digits[digits.count - 1]
    private static let lowerA = UInt8(ascii: "a")
    private static let lowerZ = UInt8(ascii: "z")
    private static let upperA = UInt8(ascii: "A")
    private static let upperZ = UInt8(ascii: "Z")
    /// The one integer below every other, which no key may be.
    private static let smallestInteger: Bytes = [upperA] + Bytes(repeating: zero, count: 26)

    /// Each byte's digit value, or -1 for a byte that isn't a digit.
    private static let values: [Int] = {
        var table = [Int](repeating: -1, count: 256)
        for (value, byte) in digits.enumerated() {
            table[Int(byte)] = value
        }
        return table
    }()

    /// The key for the first element of an empty list.
    public static let first = "a0"

    /// Whether `a` sorts before `b`.
    public static func precedes(_ a: String, _ b: String) -> Bool {
        a.utf8.lexicographicallyPrecedes(b.utf8)
    }

    public static func isValid(_ key: String) -> Bool {
        (try? validate(Bytes(key.utf8))) != nil
    }

    /// A key that sorts after `lower` and before `upper`; `nil` for either
    /// means the start or the end of the list.
    public static func between(_ lower: String?, _ upper: String?) throws -> String {
        String(decoding: try between(lower.map { Bytes($0.utf8) }, upper.map { Bytes($0.utf8) }), as: UTF8.self)
    }

    /// `count` keys in order, all after `lower` and before `upper`, spread
    /// so that none is much longer than the others.
    public static func keys(between lower: String?, _ upper: String?, count: Int) throws -> [String] {
        try keys(lower.map { Bytes($0.utf8) }, upper.map { Bytes($0.utf8) }, count)
            .map { String(decoding: $0, as: UTF8.self) }
    }

    // MARK: - Keys

    private static func keys(_ a: Bytes?, _ b: Bytes?, _ count: Int) throws -> [Bytes] {
        guard count > 0 else { return [] }
        if count == 1 { return [try between(a, b)] }
        if b == nil {
            var key = try between(a, nil)
            var result = [key]
            for _ in 1..<count {
                key = try between(key, nil)
                result.append(key)
            }
            return result
        }
        if a == nil {
            var key = try between(nil, b)
            var result = [key]
            for _ in 1..<count {
                key = try between(nil, key)
                result.append(key)
            }
            return result.reversed()
        }
        let half = count / 2
        let middle = try between(a, b)
        return try keys(a, middle, half) + [middle] + keys(middle, b, count - half - 1)
    }

    private static func between(_ a: Bytes?, _ b: Bytes?) throws -> Bytes {
        if let a { try validate(a) }
        if let b { try validate(b) }
        if let a, let b, !a.lexicographicallyPrecedes(b) {
            throw Failure.outOfOrder(string(a), string(b))
        }
        guard let a else {
            guard let b else { return Bytes(first.utf8) }
            let integer = try integerPart(b)
            let fraction = Bytes(b[integer.count...])
            if integer == smallestInteger {
                return integer + (try midpoint([], fraction))
            }
            if integer.lexicographicallyPrecedes(b) {
                return integer
            }
            guard let decremented = try decrement(integer) else { throw Failure.exhausted }
            return decremented
        }
        let integerA = try integerPart(a)
        let fractionA = Bytes(a[integerA.count...])
        guard let b else {
            if let incremented = try increment(integerA) {
                return incremented
            }
            return integerA + (try midpoint(fractionA, nil))
        }
        let integerB = try integerPart(b)
        let fractionB = Bytes(b[integerB.count...])
        if integerA == integerB {
            return integerA + (try midpoint(fractionA, fractionB))
        }
        guard let incremented = try increment(integerA) else { throw Failure.exhausted }
        if incremented.lexicographicallyPrecedes(b) {
            return incremented
        }
        return integerA + (try midpoint(fractionA, nil))
    }

    /// A fraction between `a` and `b` (`nil`: the end). Neither may end in
    /// a zero digit, or nothing could ever go between it and its own
    /// zero-padded self.
    private static func midpoint(_ a: Bytes, _ b: Bytes?) throws -> Bytes {
        if let b, !a.lexicographicallyPrecedes(b) {
            throw Failure.outOfOrder(string(a), string(b))
        }
        if a.last == zero || b?.last == zero || b?.isEmpty == true {
            throw Failure.invalid(string(a + (b ?? [])))
        }
        if let b {
            // Keep the common prefix, reading `a` as padded with zeros.
            var shared = 0
            while shared < b.count, (shared < a.count ? a[shared] : zero) == b[shared] {
                shared += 1
            }
            if shared > 0 {
                let restA = shared < a.count ? Bytes(a[shared...]) : []
                return Bytes(b[..<shared]) + (try midpoint(restA, Bytes(b[shared...])))
            }
        }
        let digitA = a.first.map { values[Int($0)] } ?? 0
        let digitB = b.map { values[Int($0[0])] } ?? digits.count
        if digitB - digitA > 1 {
            return [digits[(digitA + digitB + 1) / 2]]
        }
        if let b, b.count > 1 {
            return [b[0]]
        }
        return [digits[digitA]] + (try midpoint(Bytes(a.dropFirst()), nil))
    }

    // MARK: - The integer head

    /// How many bytes the integer part takes, head included: `a` is 2,
    /// `b` 3 … and below zero `Z` is 2, `Y` 3.
    private static func integerLength(_ head: UInt8) throws -> Int {
        switch head {
        case lowerA...lowerZ: Int(head - lowerA) + 2
        case upperA...upperZ: Int(upperZ - head) + 2
        default: throw Failure.invalid(string([head]))
        }
    }

    private static func integerPart(_ key: Bytes) throws -> Bytes {
        guard let head = key.first else { throw Failure.invalid("") }
        let length = try integerLength(head)
        guard length <= key.count else { throw Failure.invalid(string(key)) }
        return Bytes(key[..<length])
    }

    private static func validate(_ key: Bytes) throws {
        guard key != smallestInteger, key.allSatisfy({ values[Int($0)] >= 0 }) else {
            throw Failure.invalid(string(key))
        }
        let integer = try integerPart(key)
        if key.count > integer.count, key.last == zero {
            throw Failure.invalid(string(key))
        }
    }

    private static func increment(_ integer: Bytes) throws -> Bytes? {
        let head = integer[0]
        var body = Bytes(integer.dropFirst())
        var carry = true
        var index = body.count - 1
        while carry, index >= 0 {
            let value = values[Int(body[index])] + 1
            if value == digits.count {
                body[index] = zero
            } else {
                body[index] = digits[value]
                carry = false
            }
            index -= 1
        }
        guard carry else { return [head] + body }
        if head == upperZ { return [lowerA, zero] }
        if head == lowerZ { return nil }
        let nextHead = head + 1
        if nextHead > lowerA {
            body.append(zero)
        } else {
            body.removeLast()
        }
        return [nextHead] + body
    }

    private static func decrement(_ integer: Bytes) throws -> Bytes? {
        let head = integer[0]
        var body = Bytes(integer.dropFirst())
        var borrow = true
        var index = body.count - 1
        while borrow, index >= 0 {
            let value = values[Int(body[index])] - 1
            if value == -1 {
                body[index] = largestDigit
            } else {
                body[index] = digits[value]
                borrow = false
            }
            index -= 1
        }
        guard borrow else { return [head] + body }
        if head == lowerA { return [upperZ, largestDigit] }
        if head == upperA { return nil }
        let previousHead = head - 1
        if previousHead < upperZ {
            body.append(largestDigit)
        } else {
            body.removeLast()
        }
        return [previousHead] + body
    }

    private static func string(_ bytes: Bytes) -> String {
        String(decoding: bytes, as: UTF8.self)
    }
}
