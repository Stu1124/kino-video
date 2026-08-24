import Foundation

// MARK: - Curves

public enum KCurveKind: String, Codable, CaseIterable, Sendable {
    case linear
    case easeIn
    case easeOut
    case easeInOut
    case cubicBezier
    case hold
}

/// Parameterization of a cubic Bézier eased segment; anchored on v0 -> v1.
public struct KCurveSpec: Hashable, Codable, Sendable {
    public var kind: KCurveKind
    /// Control points in segment-normalized [0..1] space when kind == .cubicBezier.
    public var p1: KVec2
    public var p2: KVec2

    public init(kind: KCurveKind, p1: KVec2 = KVec2(0.42, 0), p2: KVec2 = KVec2(0.58, 1)) {
        self.kind = kind
        self.p1 = p1
        self.p2 = p2
    }

    public static let linear = KCurveSpec(kind: .linear)
    public static let easeIn = KCurveSpec(kind: .easeIn)
    public static let easeOut = KCurveSpec(kind: .easeOut)
    public static let easeInOut = KCurveSpec(kind: .easeInOut)
    public static let hold = KCurveSpec(kind: .hold)

    /// Eased progress 0..1 given linear progress 0..1.
    public func eased(_ t: Float) -> Float {
        let x = min(1, max(0, t))
        switch kind {
        case .linear: return x
        case .easeIn: return x * x * x
        case .easeOut: return 1 - pow(1 - x, 3)
        case .easeInOut: return x < 0.5 ? 4 * x * x * x : 1 - pow(-2 * x + 2, 3) / 2
        case .hold: return 0
        case .cubicBezier: return Self.bezierX(x, p1: p1, p2: p2)
        }
    }

    /// Solve y along the cubic Bézier for progress x (Newton-Raphson + bisect fallback).
    static func bezierX(_ x: Float, p1: KVec2, p2: KVec2) -> Float {
        func bezierPoint(_ t: Float, a: Float, b: Float) -> Float {
            let u = 1 - t
            return 3 * u * u * t * a + 3 * u * t * t * b + t * t * t
        }
        func bezierDerivativeX(_ t: Float) -> Float {
            let u = 1 - t
            return 3 * u * u * p1.x + 6 * u * t * (p2.x - p1.x) + 3 * t * t * (1 - p2.x)
        }
        var t = x
        for _ in 0..<8 {
            let current = bezierPoint(t, a: p1.x, b: p2.x)
            let diff = current - x
            if abs(diff) < 0.0005 { break }
            let d = bezierDerivativeX(t)
            if abs(d) > 0.00001 {
                t -= diff / d
            } else {
                break
            }
            t = min(1, max(0, t))
        }
        // bisection refine
        var lo: Float = 0, hi: Float = 1
        for _ in 0..<12 {
            let mid = (lo + hi) / 2
            if bezierPoint(mid, a: p1.x, b: p2.x) < x { lo = mid } else { hi = mid }
        }
        t = (lo + hi) / 2
        return bezierPoint(t, a: p1.y, b: p2.y)
    }
}

// MARK: - Keyframes

/// Values are Float scalars. Vector properties (position) use one channel per component,
/// which keeps interpolation deterministic and cross-platform identical.
public struct Keyframe: Hashable, Codable, Sendable {
    /// Timeline time (clip's canvas start = 0) when this keyframe applies.
    public var time: KTime
    public var value: Float
    /// Easing to use when travelling FROM this segment's previous key TO this key.
    /// Stored on the arriving key; the first key's spec is ignored.
    public var curve: KCurveSpec

    public init(time: KTime, value: Float, curve: KCurveSpec = .linear) {
        self.time = time
        self.value = value
        self.curve = curve
    }
}

/// Ordered keyframes for a single animated property.
public struct KChannel: Hashable, Codable, Sendable {
    public var property: String
    public var keyframes: [Keyframe] // sorted by time

    public init(property: String, keyframes: [Keyframe] = []) {
        self.property = property
        self.keyframes = keyframes
    }

    /// Value at local time t. Before first key: first key value (or default).
    /// After last key: last key value.
    public func evaluate(_ t: KTime, defaultValue: Float = 0) -> Float {
        guard let first = keyframes.first else { return defaultValue }
        guard t >= first.time else { return first.value }
        guard let last = keyframes.last, t < last.time else {
            return keyframes.last?.value ?? first.value
        }
        for i in 1..<keyframes.count {
            let k0 = keyframes[i - 1]
            let k1 = keyframes[i]
            if t >= k0.time && t < k1.time {
                let span = k1.time.ns - k0.time.ns
                guard span > 0 else { return k1.value }
                let linear = Float(t.ns - k0.time.ns) / Float(span)
                let eased = k1.curve.eased(linear)
                return k0.value + (k1.value - k0.value) * eased
            }
        }
        return last.value
    }

    public mutating func upsert(_ keyframe: Keyframe) {
        // exact-time replace
        keyframes.removeAll { abs($0.time.ns - keyframe.time.ns) < 1 }
        keyframes.append(keyframe)
        keyframes.sort { $0.time.ns < $1.time.ns }
    }

    public mutating func remove(at time: KTime) {
        keyframes.removeAll { abs($0.time.ns - time.ns) < 1 }
    }

    public func nearestKey(time: KTime, tolerance: KTime? = nil) -> Keyframe? {
        keyframes.min { a, b in
            abs(a.time.ns - time.ns) < abs(b.time.ns - time.ns)
        }
    }
}

/// A keyed clip: channels keyed by property name.
public struct KeyframeStore: Hashable, Codable, Sendable {
    public var channels: [String: KChannel]

    public init(channels: [String: KChannel] = [:]) { self.channels = channels }

    /// True when a key exists at (within 1ns of) the given time on any channel.
    public func hasKey(at t: KTime) -> Bool {
        channels.values.contains { $0.keyframes.contains { abs($0.time.ns - t.ns) < 1 } }
    }

    /// Adds/updates a key at time t for every annotated property (each with its current value).
    public mutating func setKeys(at t: KTime, properties: [String: Float], curve: KCurveSpec = .linear) {
        for (prop, value) in properties {
            var ch = channels[prop] ?? KChannel(property: prop)
            var kf: Keyframe
            if let existing = ch.keyframes.first(where: { abs($0.time.ns - t.ns) < 1 }) {
                kf = existing
            } else {
                kf = Keyframe(time: t, value: value)
            }
            kf.value = value
            kf.time = t
            kf.curve = curve
            ch.upsert(kf)
            channels[prop] = ch
        }
    }

    public mutating func removeKeys(at t: KTime) {
        for (prop, var ch) in channels {
            let before = ch.keyframes.count
            ch.remove(at: t)
            if ch.keyframes.count != before {
                channels[prop] = ch
            }
        }
    }

    /// Evaluate every channel at local time; returns property -> value map.
    public func evaluateAll(_ t: KTime) -> [String: Float] {
        var out: [String: Float] = [:]
        for (prop, ch) in channels {
            out[prop] = ch.evaluate(t, defaultValue: {
                switch prop { default: return 0 }
            }())
        }
        return out
    }

    public static let empty = KeyframeStore()
}
