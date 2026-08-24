import Foundation

/// Mapping between source time and timeline (canvas) time for a clip's speed spec.
/// The preview and the export renderer must both use *exactly* this mapping so that
/// the exported video matches what the editor showed.
public enum SpeedMath {

    /// Timeline (display) duration occupied by `source` seconds of media under `speed`.
    public static func displayDuration(source: KTime, speed: SpeedSpec) -> KTime {
        let d = Double(source.seconds)
        guard d > 0 else { return .zero }
        let avg = speed.curve.isEmpty
            ? Double(speed.rate)
            : averageRate(speed)
        guard avg > 0.0001 else { return KTime(seconds: d) }
        return KTime(seconds: d / avg)
    }

    public static func sourceToDisplay(_ source: KTime, speed: SpeedSpec) -> KTime {
        let d = Double(source.seconds)
        let avg = speed.curve.isEmpty ? Double(speed.rate) : averageRate(speed)
        guard avg > 0 else { return .zero }
        return KTime(seconds: d / avg)
    }

    public static func displayToSource(_ display: KTime, speed: SpeedSpec) -> KTime {
        let d = Double(display.seconds)
        let avg = speed.curve.isEmpty ? Double(speed.rate) : averageRate(speed)
        return KTime(seconds: d * avg)
    }

    /// Average rate over the clip (numeric integral of the curve).
    public static func averageRate(_ speed: SpeedSpec, steps: Int = 128) -> Double {
        guard !speed.curve.isEmpty else { return Double(speed.rate) }
        var sum = 0.0
        for i in 0..<steps {
            let p = (Double(i) + 0.5) / Double(steps)
            sum += Double(rateAt(progress: Float(p), speed: speed))
        }
        return sum / Double(steps)
    }

    /// Rate multiplier at normalized timeline progress [0..1], interpolated smoothly.
    public static func rateAt(progress p: Float, speed: SpeedSpec) -> Float {
        guard !speed.curve.isEmpty else { return speed.rate }
        var points = speed.curve.sorted { $0.position < $1.position }
        if (points.first?.position ?? 1) > 0 {
            points.insert(SpeedCurvePoint(position: 0, rate: points.first?.rate ?? speed.rate), at: 0)
        }
        if (points.last?.position ?? 0) < 1 {
            points.append(SpeedCurvePoint(position: 1, rate: points.last?.rate ?? speed.rate))
        }
        for i in 1..<points.count {
            let a = points[i - 1], b = points[i]
            if p >= a.position && p <= b.position {
                let span = b.position - a.position
                guard span > 0 else { return b.rate }
                let t = (p - a.position) / span
                let eased = t * t * (3 - 2 * t) // smoothstep = continuous, monotone
                return a.rate + (b.rate - a.rate) * eased
            }
        }
        return speed.rate
    }

    /// Source progress (0..1 through the clip's source range) at a given timeline progress.
    /// sourceProgress = d(display)/d(rate) — integrates the rate curve.
    public static func sourceProgress(atTimelineProgress p: Float, speed: SpeedSpec, steps: Int = 128) -> Float {
        guard !speed.curve.isEmpty else { return min(1, max(0, p)) }
        let clamped = min(1, max(0, p))
        let dt = 1.0 / Double(steps)
        var src = 0.0
        var d = 0.0
        while d < Double(clamped) {
            let rate = Double(rateAt(progress: Float(min(d, Double(clamped))), speed: speed))
            src += rate * dt
            d += dt
        }
        // normalise so that source(1.0) == 1.0 exactly (curve self-consistency)
        let full = fullSourceIntegral(speed, steps: steps)
        guard full > 0 else { return min(1, Float(src)) }
        return Float(src / full)
    }

    /// Timeline progress given a source progress (inverse of sourceProgress).
    public static func timelineProgress(forSourceProgress p: Float, speed: SpeedSpec, steps: Int = 128) -> Float {
        guard !speed.curve.isEmpty else { return min(1, max(0, p)) }
        let target = min(1, max(0, p))
        let full = fullSourceIntegral(speed, steps: steps)
        guard full > 0 else { return target }
        let desired = Double(target) * full
        var src = 0.0
        for i in 0...steps {
            // step down in display units, accumulating source
            let t = Double(i) / Double(steps)
            let srcNow = src
            _ = srcNow
            if src >= desired {
                let tPrev = Double(i - 1) / Double(steps)
                let srcPrev = src - Double(rateAt(progress: Float(tPrev), speed: speed)) / Double(steps)
                let frac = (desired - srcPrev) / max((src - srcPrev), 1e-9)
                return Float(min(1, tPrev + frac / Double(steps)))
            }
            if i < steps {
                src += Double(rateAt(progress: Float(t), speed: speed)) / Double(steps)
            }
        }
        return 1
    }

    static func fullSourceIntegral(_ speed: SpeedSpec, steps: Int) -> Double {
        var full = 0.0
        for i in 0..<steps {
            full += Double(rateAt(progress: (Float(i) + 0.5) / Float(steps), speed: speed)) / Double(steps)
        }
        return full
    }

    /// Source time on the asset that appears at `offset` into the clip (curve-aware).
    /// `offset` is display time since the clip's start; caller applies `reversed` flag on top.
    public static func sourceTime(atDisplay offset: KTime, clip: Clip) -> KTime {
        let totalNs = clip.sourceRange.duration.ns
        guard totalNs > 0 else { return clip.sourceRange.start }
        if clip.speed.curve.isEmpty {
            let d = KTime(seconds: Double(offset.seconds) * Double(clip.speed.rate))
            let raw = clip.sourceRange.start + d
            return KTime.min(KTime.max(raw, clip.sourceRange.start), clip.sourceRange.end)
        }
        let prog = Float(min(1, max(0, Double(offset.seconds) / Double(clip.duration.seconds))))
        let srcProg = sourceProgress(atTimelineProgress: prog, speed: clip.speed)
        return clip.sourceRange.start + KTime(seconds: Double(srcProg) * Double(totalNs) / 1_000_000_000.0)
    }

    /// Display offset that shows source time `t`.
    public static func displayTime(forSource source: KTime, clip: Clip) -> KTime {
        let totalNs = clip.sourceRange.duration.ns
        guard totalNs > 0 else { return .zero }
        if clip.speed.curve.isEmpty {
            let s = Double((source - clip.sourceRange.start).seconds) / Double(clip.speed.rate)
            return KTime(seconds: s)
        }
        let rel = Double((source - clip.sourceRange.start).seconds) / (Double(totalNs) / 1_000_000_000.0)
        let prog = timelineProgress(forSourceProgress: Float(rel), speed: clip.speed)
        return KTime(seconds: Double(clip.duration.seconds) * Double(prog))
    }
}

// MARK: - Rational from Float

extension Rational {
    /// Simple decimal expansion of a float rate up to 1e-6 precision, 5 fraction digits max.
    init(ratio: Double) {
        let r = ratio <= 0 ? 1 : ratio  // float rate; never reassigned
        var den = 1.0
        while abs(r * den - (r * den).rounded()) > 1e-6 && den < 10_000 {
            den *= 10
        }
        let num = Int64((r * den).rounded())
        self.init(num, Int64(den))
    }
}

extension KTime {
    /// Scale by a float factor using the closest rational approximation.
    public func scaled(by factor: Float) -> KTime {
        let r = Rational(ratio: Double(factor))
        guard r.den <= 10_000, r.num > 0 else {
            return KTime(seconds: seconds * Double(factor))
        }
        return scaled(by: r)
    }
}
