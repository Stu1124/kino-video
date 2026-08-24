import Foundation

/// 128-bit unsigned integer helper (double-word) for exact multiply/divide on 64-bit hardware.
struct U128 {
    var high: UInt64
    var low: UInt64

    init(_ value: UInt64) { high = 0; low = value }
    init(high: UInt64, low: UInt64) { self.high = high; self.low = low }

    func add(_ o: U128) -> U128 {
        let (lo, carry) = low.addingReportingOverflow(o.low)
        return U128(high: carry ? high &+ o.high &+ 1 : high &+ o.high, low: lo)
    }

    func shiftedLeft(by k: Int) -> U128 {
        guard k > 0 else { return self }
        if k >= 64 {
            let r = k - 64
            guard r < 64 else { return U128(0) }
            return U128(high: low << r, low: 0)
        }
        return U128(high: (high << k) | (low >> (64 - k)), low: low << k)
    }

    static func mul(_ a: UInt64, _ b: UInt64) -> U128 {
        let a0 = a & 0xFFFF_FFFF, a1 = a >> 32
        let b0 = b & 0xFFFF_FFFF, b1 = b >> 32
        let p00 = U128(a0 &* b0)
        let p01 = U128(a0 &* b1).shiftedLeft(by: 32)
        let p10 = U128(a1 &* b0).shiftedLeft(by: 32)
        let p11 = U128(a1 &* b1).shiftedLeft(by: 64)
        return p00.add(p01).add(p10).add(p11)
    }

    func divided(by divisor: UInt64) -> (quotient: UInt64, remainder: UInt64)? {
        precondition(divisor > 0)
        if high < divisor {
            // simple 64-bit division path is not possible; use bitwise long division
            var rem: UInt64 = 0
            var q: UInt64 = 0
            for i in stride(from: 127, through: 0, by: -1) {
                rem = (rem << 1) | bit(i)
                if rem >= divisor {
                    rem -= divisor
                    q |= (1 << i)
                }
            }
            return (q, rem)
        } else if high == 0 {
            return (low / divisor, low % divisor)
        } else {
            // quotient does not fit in 64 bits
            return nil
        }
    }

    func bit(_ i: Int) -> UInt64 {
        i < 64 ? (low >> i) & 1 : (high >> (i - 64)) & 1
    }
}

/// Overflow-safe `(a * b) / c` returning nil when the result exceeds Int64 range.
enum ExactMulDiv {
    static func mulDiv(_ a: Int64, _ b: Int64, _ c: Int64) -> Int64? {
        precondition(c > 0)
        guard a != 0, b != 0 else { return 0 }
        let neg = (a < 0) != (b < 0)
        let ua = UInt64(a.magnitude)
        let ub = UInt64(b.magnitude)
        let uc = UInt64(c.magnitude)
        let p = U128.mul(ua, ub)
        guard let (q, _) = p.divided(by: uc) else { return nil }
        if neg {
            if q > (1 << 63) { return nil }
            return q == (1 << 63) ? Int64.min : -Int64(q)
        }
        if q > UInt64(Int64.max) { return nil }
        return Int64(q)
    }
}

// MARK: - Time

/// A frame-accurate time value backed by integer nanoseconds.
public struct KTime: Hashable, Codable, Sendable, Comparable, CustomStringConvertible {
    public var ns: Int64

    public init(ns: Int64) { self.ns = ns }
    public init(milliseconds: Double) { self.ns = Int64((milliseconds * 1_000_000).rounded()) }
    public init(seconds: Double) { self.ns = Int64((seconds * 1_000_000_000).rounded()) }

    public static let zero = KTime(ns: 0)

    public static func < (lhs: KTime, rhs: KTime) -> Bool { lhs.ns < rhs.ns }

    public static func + (lhs: KTime, rhs: KTime) -> KTime { KTime(ns: lhs.ns + rhs.ns) }
    public static func - (lhs: KTime, rhs: KTime) -> KTime { KTime(ns: lhs.ns - rhs.ns) }

    /// Multiply by a rational factor exactly. Used for speed mapping.
    public func scaled(by f: Rational) -> KTime {
        guard let r = ExactMulDiv.mulDiv(ns, f.num, f.den) else {
            return KTime(ns: ns) // overflow; fall back to float approximation
        }
        return KTime(ns: r)
    }

    public var seconds: Double { Double(ns) / 1_000_000_000.0 }
    public var milliseconds: Double { Double(ns) / 1_000_000.0 }

    public static func min(_ a: KTime, _ b: KTime) -> KTime { a <= b ? a : b }
    public static func max(_ a: KTime, _ b: KTime) -> KTime { a >= b ? a : b }

    public func clamped(to range: TimeRange) -> KTime {
        KTime.min(KTime.max(self, range.start), range.end)
    }

    public var description: String { String(format: "%.3f", seconds) + "s" }
}

// MARK: - Rational

/// Exact rational frame rate, e.g. 29.97 = 2997/100.
public struct Rational: Hashable, Codable, Sendable, CustomStringConvertible {
    public var num: Int64
    public var den: Int64

    public init(_ num: Int64, _ den: Int64) {
        precondition(den > 0, "denominator must be positive")
        let g = Self.gcd(num.magnitude, den.magnitude)
        self.num = num / Int64(max(g &* (g > 0 ? 1 : 1), 1))
        self.den = den / Int64(max(g, 1))
        if self.num == 0 { self.den = 1 }
    }

    static func gcd(_ a: UInt64, _ b: UInt64) -> UInt64 {
        var a = a, b = b
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    public static let fps2397 = Rational(24000, 1001)
    public static let fps24 = Rational(24, 1)
    public static let fps25 = Rational(25, 1)
    public static let fps2997 = Rational(2997, 100)
    public static let fps30 = Rational(30, 1)
    public static let fps50 = Rational(50, 1)
    public static let fps60 = Rational(60, 1)
    public static let fps120 = Rational(120, 1)
    public static let fps240 = Rational(240, 1)

    public static let common = [Rational.fps2397, .fps24, .fps25, .fps2997, .fps30, .fps50, .fps60, .fps120]

    public var double: Double { Double(num) / Double(den) }

    /// 23.976 vs 24 disambiguation when a rate's real fps is human-typed.
    public var isNTSC: Bool {
        Swift.abs(num * 100 - den * 2997) < den * 100 / 1000 ||
        Swift.abs(num * 100 - den * 24000 / 100 * 100) == den * 100
    }

    public var description: String { "\(num)/\(den)" }

    /// Number of frames elapsed at this rate over a duration, exact rational math.
    public func frames(in duration: KTime) -> Int64 {
        guard duration.ns > 0 else { return 0 }
        guard let f = ExactMulDiv.mulDiv(duration.ns, num, 1_000_000_000 * den) else {
            return Int64(Double(duration.ns) / 1_000_000_000 * double)
        }
        return f
    }

    /// Index of the frame containing time (0-based, clamped at 0).
    public func frameIndex(at time: KTime) -> Int64 {
        max(0, frames(in: time) - 1)
    }

    /// First exact start instant of frame index i (ceil semantics), so that
    /// `frames(in: frameStart(i)) >= i` holds wherever the grid permits.
    public func frameStart(_ i: Int64) -> KTime {
        guard i > 0 else { return .zero }
        let target = 1_000_000_000 * den * i
        guard let q = ExactMulDiv.mulDiv(1_000_000_000 * den, i, num) else {
            return KTime(seconds: Double(i) / double)
        }
        // floor result; step up if truncation fell short of the exact instant
        return KTime(ns: q * num == target ? q : q + 1)
    }

    /// Total frames over an entire clip that spans `duration` exactly.
    public func frameCount(for duration: KTime) -> Int64 { frames(in: duration) }

    public func time(ofFrame i: Int64) -> KTime { frameStart(i) }
}

// MARK: - TimeRange

public struct TimeRange: Hashable, Codable, Sendable, CustomStringConvertible {
    public var start: KTime
    public var end: KTime

    public init(start: KTime, end: KTime) {
        self.start = start
        self.end = end
    }

    public init(start: KTime, duration: KTime) {
        self.start = start
        self.end = start + duration
    }

    public var duration: KTime { end - start }
    public var isEmpty: Bool { end <= start }

    public func contains(_ t: KTime) -> Bool { t >= start && t < end }
    public func contains(_ r: TimeRange) -> Bool { r.start >= start && r.end <= end }
    public func intersects(_ r: TimeRange) -> Bool { r.end > start && r.start < end }

    public func clamped(to r: TimeRange) -> TimeRange {
        TimeRange(start: KTime.max(start, r.start), end: KTime.min(end, r.end))
    }

    public var description: String { "[\(start) ... \(end))" }

    public static let zero = TimeRange(start: .zero, end: .zero)
}
