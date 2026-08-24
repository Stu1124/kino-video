import AVFoundation
import KinoEngine

// MARK: - KTime <-> CMTime

public extension KTime {
    init(_ t: CMTime) {
        var s = t.seconds
        if !s.isFinite { s = 0 }
        let sec = s
        self = KTime(ns: Int64((sec * 1_000_000_000).rounded()))
    }

    var cmTime: CMTime {
        CMTime(value: CMTimeValue(ns), timescale: 1_000_000_000)
    }
}

public extension Rational {
    var frameDuration: CMTime {
        // 1/29.97fps -> denominator as numerator/denominator of seconds
        CMTime(value: CMTimeValue(den), timescale: CMTimeScale(num))
    }
}

public extension AVAssetTrack {
    var kinoNaturalSize: KVec2 {
        let s = naturalSize
        guard s.width > 0, s.height > 0 else { return KVec2(0, 0) }
        return KVec2(Float(s.width), Float(s.height))
    }
}

public extension TimeRange {
    var cmRange: CMTimeRange {
        CMTimeRange(start: start.cmTime, end: end.cmTime)
    }
}

public extension CMTimeRange {
    var kinoRange: TimeRange { TimeRange(start: KTime(start), end: KTime(end)) }
}
