import XCTest
@testable import KinoEngine

final class AudioDSPTests: XCTestCase {

    func synthClick(_ atSeconds: Double, sampleRate: Double) -> [Float] {
        var out = [Float](repeating: 0, count: 0)
        let len = max(8, Int(0.012 * sampleRate))
        for i in 0..<len {
            out.append(Float(Double(i) / Double(len)) * Float(sin(2 * .pi * 1000 * Double(i) / sampleRate)) * 0.9)
        }
        return out
    }

    func signal(clickEvery secs: Double, duration: Double, sampleRate: Double, startAt: Double = 0.5) -> [Float] {
        var samples = [Float](repeating: 0, count: Int(duration * sampleRate))
        var t = startAt
        while t < duration {
            let c = synthClick(t, sampleRate: sampleRate)
            let base = Int(t * sampleRate)
            for (i, v) in c.enumerated() {
                if base + i < samples.count { samples[base + i] = v }
            }
            t += secs
        }
        return samples
    }

    func testWaveformBucketCount() {
        let sr = 44100.0
        let samples = [Float](repeating: 0.5, count: Int(0.6 * sr))
        let wf = AudioWaveform.fromSamples(samples, sampleRate: sr, bucketDuration: KTime(milliseconds: 33))
        XCTAssertEqual(wf.peaks.count, 19, "0.6s at 33ms buckets ≈ 18.2 → 19 buckets")
        XCTAssertEqual(wf.peakMax, 1.0, "normalized to max 1")
        XCTAssertEqual(wf.totalDuration.milliseconds, 19 * 33, accuracy: 1)
    }

    func testWaveformSilence() {
        let samples = [Float](repeating: 0, count: 44100)
        let wf = AudioWaveform.fromSamples(samples, sampleRate: 44100, bucketDuration: KTime(milliseconds: 100))
        XCTAssertEqual(wf.peakMax, 0)
    }

    func testOnsetDetectionClicks() {
        let sr = 22050.0
        let samples = signal(clickEvery: 0.5, duration: 2.0, sampleRate: sr)
        let onsets = OnsetDetector.detectOnsets(samples: samples, sampleRate: sr, hop: 256)
        XCTAssertGreaterThanOrEqual(onsets.count, 3, "expect ~4 onsets for clicks at 0.5,1,1.5")
        for (i, o) in onsets.prefix(4).enumerated() {
            let expected = 0.5 + Double(i) * 0.5
            XCTAssertEqual(o.time.seconds, expected, accuracy: 0.06, "onset \(i) should land at click")
            XCTAssertGreaterThanOrEqual(o.strength, 0.2)
        }
    }

    func testDominantInterval() {
        let sr = 22050.0
        let samples = signal(clickEvery: 0.5, duration: 2.5, sampleRate: sr)
        let onsets = OnsetDetector.detectOnsets(samples: samples, sampleRate: sr, hop: 256)
        let interval = BeatTools.dominantInterval(onsets: onsets)
        XCTAssertNotNil(interval)
        XCTAssertEqual(interval!, 0.5, accuracy: 0.03)
    }

    func testBeatGridAndSnap() {
        let grid = BeatTools.beatGrid(tempoSeconds: 0.5, phase: .zero, duration: KTime(seconds: 2))
        XCTAssertEqual(grid.count, 4)  // 0, 0.5, 1.0, 1.5 (2.0 excluded: half-open)
        XCTAssertEqual(grid[3].seconds, 1.5, accuracy: 0.001)

        let raw = [Onset(time: KTime(seconds: 0.47), strength: 1),
                   Onset(time: KTime(seconds: 1.03), strength: 1)]
        let snapped = BeatTools.snapOnsets(raw, toTempo: 0.5, phaseFrom: .zero)
        XCTAssertEqual(snapped[0].time.seconds, 0.5, accuracy: 0.0001)
        XCTAssertEqual(snapped[1].time.seconds, 1.0, accuracy: 0.0001)
    }

    func testSilenceDetection() {
        let sr = 22050.0
        var samples = [Float](repeating: 0.4, count: Int(sr)) // 1s of audio
        for i in Int(0.3 * sr)..<Int(0.7 * sr) { samples[i] = 0 } // 0.4s silence
        let silences = SilenceDetector.detectSilences(samples: samples, sampleRate: sr, threshold: 0.01, minSilence: KTime(milliseconds: 300))
        XCTAssertEqual(silences.count, 1)
        XCTAssertEqual(silences[0].start.seconds, 0.3, accuracy: 0.05)
        XCTAssertEqual(silences[0].end.seconds, 0.7, accuracy: 0.05)
    }

    func testAudioMath() {
        XCTAssertEqual(AudioMath.gain(fromDB: 0), 1, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.db(fromGain: 1), 0, accuracy: 0.0001)
        XCTAssertEqual(AudioMath.gain(fromDB: -6), 0.5012, accuracy: 0.001)
    }

    func testEnvelope() {
        let sr = 44100.0
        var samples = [Float](repeating: 1, count: Int(0.5 * sr))
        AudioMath.applyEnvelope(&samples, volume: 1, fadeIn: KTime(seconds: 0.25), fadeOut: .zero, sampleRate: sr)
        let mid = samples[samples.count / 2] // t=0.25 → fade fully applied
        XCTAssertEqual(mid, 1.0, accuracy: 0.001)
        let quarter = samples[samples.count / 4] // t=0.125 → 50%
        XCTAssertEqual(quarter, 0.5, accuracy: 0.05)
    }
}
