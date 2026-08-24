import Foundation

// MARK: - Waveform

public struct AudioPeak: Hashable, Codable, Sendable {
    public var value: Float
    public var time: KTime

    public init(value: Float, time: KTime) {
        self.value = value
        self.time = time
    }
}

public struct AudioWaveform: Hashable, Codable, Sendable {
    public var peaks: [AudioPeak]
    public var bucketDuration: KTime
    public var sampleRate: Double

    public init() {
        peaks = []
        bucketDuration = KTime(ns: 33_333_333)
        sampleRate = 44100
    }

    /// monophonic samples in [-1..1]; per-bucket peak amplitude (max |sample|).
    public static func fromSamples(_ samples: [Float], sampleRate: Double, bucketDuration: KTime) -> AudioWaveform {
        let bucketNs = max(bucketDuration.ns, 1)
        var wf = AudioWaveform()
        wf.sampleRate = sampleRate
        wf.bucketDuration = bucketDuration
        guard !samples.isEmpty else { return wf }
        let samplesPerBucket = max(1, Int(Double(bucketNs) / 1_000_000_000.0 * sampleRate))
        var bucketMax: Float = 0
        var bx = 0
        var peaks: [AudioPeak] = []
        var globalMax: Float = 0
        for s in samples {
            let a = abs(s)
            if a > bucketMax { bucketMax = a }
            if a > globalMax { globalMax = a }
            bx += 1
            if bx >= samplesPerBucket {
                peaks.append(AudioPeak(value: bucketMax, time: KTime(ns: Int64(peaks.count) * bucketNs)))
                bucketMax = 0
                bx = 0
            }
        }
        if bx > 0 {
            peaks.append(AudioPeak(value: bucketMax, time: KTime(ns: Int64(peaks.count) * bucketNs)))
        }
        // normalize
        if globalMax > 0.0001 {
            var norm: [AudioPeak] = []
            norm.reserveCapacity(peaks.count)
            for p in peaks {
                norm.append(AudioPeak(value: p.value / globalMax, time: p.time))
            }
            peaks = norm
        }
        wf.peaks = peaks
        return wf
    }

    public var peakMax: Float {
        peaks.reduce(0) { Swift.max($0, $1.value) }
    }

    public var totalDuration: KTime {
        KTime(ns: bucketDuration.ns * Int64(peaks.count))
    }

    public func peak(at t: KTime) -> Float {
        guard !peaks.isEmpty else { return 0 }
        let idx = Swift.min(peaks.count - 1, Swift.max(0, Int(t.ns / Swift.max(bucketDuration.ns, 1))))
        return peaks[idx].value
    }
}

// MARK: - Onset detection

public struct Onset: Hashable, Codable, Sendable {
    public var time: KTime
    public var strength: Float
    public init(time: KTime, strength: Float) {
        self.time = time
        self.strength = strength
    }
}

public enum OnsetDetector {
    /// Energy-flux onset detection with adaptive thresholding. Pure Swift; intended for
    /// downsampled mono material (24kHz or lower). Threshold multiplier relative to
    /// a slow moving average of the flux; min separation defeats double-triggers.
    public static func detectOnsets(samples: [Float],
                                    sampleRate: Double,
                                    hop: Int = 256,
                                    threshold: Float = 1.5,
                                    minSeparation: Double = 0.08) -> [Onset] {
        guard samples.count >= hop * 4 else { return [] }
        let hopDouble = Double(hop)
        // short-term energy per hop window (rectangular; fine for flux)
        var energy: [Double] = []
        var i = 0
        while i + hop <= samples.count {
            var e: Double = 0
            for k in i..<(i + hop) {
                e += Double(samples[k]) * Double(samples[k])
            }
            energy.append(e / hopDouble)
            i += hop
        }
        guard energy.count > 4 else { return [] }

        // spectral/time flux: positive energy difference
        var flux: [Double] = [0]
        for idx in 1..<energy.count {
            flux.append(Swift.max(0, energy[idx] - energy[idx - 1]))
        }

        // adaptive threshold: moving average of flux over ~0.5s window (i.e. winLen hops)
        let winLen = Swift.max(3, Int(0.5 * sampleRate / hopDouble))
        var onsets: [Onset] = []
        var lastOnsetIdx = -Int.max
        for idx in 0..<flux.count {
            let lo = Swift.max(0, idx - winLen)
            let hi = Swift.min(flux.count, idx + winLen)
            var mean: Double = 0
            for j in lo..<hi { mean += flux[j] }
            mean /= Double(hi - lo)
            let meanLocal = Swift.max(mean, 1e-9)
            if flux[idx] > Double(threshold) * meanLocal {
                let dt = (Double(idx) - Double(lastOnsetIdx)) * hopDouble / sampleRate
                if dt >= minSeparation {
                    let strength = Float(Swift.min(1, flux[idx] / (meanLocal * 4 + flux[idx])))
                    onsets.append(Onset(time: KTime(seconds: Double(idx) * hopDouble / sampleRate),
                                        strength: strength))
                    lastOnsetIdx = idx
                }
            }
        }
        return onsets
    }
}

// MARK: - Beat tools

public enum BeatTools {
    /// Most common inter-onset interval via histogram binning (bin width 20ms).
    public static func dominantInterval(onsets: [Onset]) -> Double? {
        guard onsets.count >= 2 else { return nil }
        var histogram: [Int64: Int] = [:]
        for i in 1..<onsets.count {
            let deltaNanos = onsets[i].time.ns - onsets[i - 1].time.ns
            guard deltaNanos > 0 else { continue }
            // 20ms bins
            let bin = deltaNanos / 20_000_000
            histogram[bin, default: 0] += 1
        }
        guard let best = histogram.max(by: { $0.value < $1.value || ($0.value == $1.value && $0.key < $1.key) }) else {
            return nil
        }
        return Double(best.key * 20_000_000) / 1_000_000_000.0
    }

    /// Snap onsets to the nearest beat multiple from a phase time.
    public static func snapOnsets(_ onsets: [Onset], toTempo tempoSeconds: Double, phaseFrom phase: KTime) -> [Onset] {
        guard tempoSeconds > 0.001 else { return onsets }
        return onsets.map { o in
            let relNanos = Double(o.time.ns - phase.ns)
            let beats = (relNanos / (tempoSeconds * 1_000_000_000)).rounded()
            return Onset(time: phase + KTime(ns: Int64(beats * tempoSeconds * 1_000_000_000)),
                         strength: o.strength)
        }
    }

    /// Beat grid times from phase over duration.
    public static func beatGrid(tempoSeconds: Double, phase: KTime, duration: KTime) -> [KTime] {
        guard tempoSeconds > 0.001 else { return [] }
        var out: [KTime] = []
        var t = phase
        let end = phase + duration
        while t < end {
            out.append(t)
            t = t + KTime(seconds: tempoSeconds)
        }
        return out
    }
}

// MARK: - Silence & loudness

public enum SilenceDetector {
    /// Segments where RMS below threshold (linear) for at least minDuration.
    public static func detectSilences(samples: [Float],
                                      sampleRate: Double,
                                      threshold: Float = 0.01,
                                      minSilence: KTime = KTime(milliseconds: 400),
                                      hop: Int = 512) -> [TimeRange] {
        guard samples.count > hop else { return [] }
        var ranges: [TimeRange] = []
        var i = 0
        var segStart: Double? = nil
        while i + hop <= samples.count {
            var e: Double = 0
            for k in i..<(i + hop) {
                e += Double(samples[k]) * Double(samples[k])
            }
            let rms = Float(sqrt(e / Double(hop)))
            let t = Double(i) / sampleRate
            if rms < threshold {
                if segStart == nil { segStart = t }
            } else {
                if let s = segStart {
                    let dur = t - s
                    if dur >= minSilence.seconds {
                        ranges.append(TimeRange(start: KTime(seconds: s), end: KTime(seconds: t)))
                    }
                    segStart = nil
                }
            }
            i += hop
        }
        if let s = segStart {
            let dur = Double(samples.count) / sampleRate - s
            if dur >= minSilence.seconds {
                ranges.append(TimeRange(start: KTime(seconds: s), end: KTime(seconds: Double(samples.count) / sampleRate)))
            }
        }
        return ranges
    }

    /// Peak-normalize to 0.98.
    public static func peakNormalized(_ samples: [Float]) -> [Float] {
        var peak: Float = 0
        for s in samples { peak = Swift.max(peak, abs(s)) }
        guard peak > 0.000001 else { return samples }
        let g = 0.98 / peak
        return samples.map { $0 * g }
    }
}

// MARK: - Audio math & envelopes

public enum AudioMath {
    public static func gain(fromDB db: Float) -> Float {
        Float(pow(10.0, Double(db) / 20.0))
    }

    public static func db(fromGain gain: Float) -> Float {
        Float(20 * log10(Double(Swift.max(gain, 0.0001))))
    }

    /// Applies volume + fades to samples (in place). fades are over the entire buffer.
    public static func applyEnvelope(_ samples: inout [Float],
                                     volume: Float,
                                     fadeIn: KTime,
                                     fadeOut: KTime,
                                     sampleRate: Double) {
        guard !samples.isEmpty else { return }
        let n = Float(samples.count)
        let fi = Float(fadeIn.seconds)
        let fo = Float(fadeOut.seconds)
        let total = n / Float(sampleRate)
        for i in 0..<samples.count {
            var g = volume
            let t = Float(i) / Float(sampleRate)
            if fi > 0.000001 && t < fi {
                let p = fi <= 0 ? 1 : t / fi
                g *= min(1, p)
            }
            if fo > 0.000001 && t > total - fo {
                let p = fo <= 0 ? 1 : (total - t) / fo
                g *= min(1, p)
            }
            samples[i] *= min(2, max(0, g))
        }
    }
}
