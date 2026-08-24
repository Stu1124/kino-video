import XCTest
@testable import KinoEngine

final class KTimeTests: XCTestCase {

    func testExactMulDiv() {
        XCTAssertEqual(ExactMulDiv.mulDiv(1_000_000_000, 2997, 100), 29_970_000_000)
        XCTAssertEqual(ExactMulDiv.mulDiv(1_000_000_000, 24000, 1001), 23_976_023_976)
        XCTAssertEqual(ExactMulDiv.mulDiv(-1_000_000_000, 24000, 1001), -23_976_023_976)
        XCTAssertNil(ExactMulDiv.mulDiv(Int64.max, Int64.max, 1))
        XCTAssertEqual(ExactMulDiv.mulDiv(Int64.min, -1, 1), nil) // overflow clamped
        XCTAssertEqual(ExactMulDiv.mulDiv(0, 123456789, 7), 0)
    }

    func testRationalReduction() {
        let r = Rational(60000, 2000)
        XCTAssertEqual(r.num, 30)
        XCTAssertEqual(r.den, 1)
    }

    func testFrameConversion29_97() {
        let fps = Rational(2997, 100)
        // one second of 29.97fps material -> 29 full frames elapsed plus a smidge
        let oneSec = KTime(seconds: 1.0)
        XCTAssertEqual(fps.frames(in: oneSec), 29)
    }

    func testFrameStartMonotonicAllRates() {
        for fps in [Rational.fps24, .fps2397, .fps2997, .fps30, .fps60] {
            for i in 0..<200 {
                let start = fps.frameStart(Int64(i))
                let next = fps.frameStart(Int64(i) + 1)
                XCTAssertLessThan(start, next, "frame start times must advance")
            }
        }
    }

    func testFrameStartInversion24fps() {
        let fps = Rational.fps24
        for i in 0..<400 {
            let t = fps.frameStart(Int64(i))
            XCTAssertEqual(fps.frames(in: t), Int64(i), "frame n starts exactly when n frames have elapsed")
            let d20 = fps.frameStart(Int64(0))
            XCTAssertEqual(fps.frames(in: d20), 0)
        }
    }

    func testFrameStartInversionNTSCWithinOneFrame() {
        for fps in [Rational.fps2397, .fps2997] {
            for i in 0..<200 {
                let t = fps.frameStart(Int64(i))
                let count = fps.frames(in: t)
                XCTAssertLessThanOrEqual(Swift.abs(count - Int64(i)), 1, "NTSC rates are +/-1 frame on the ns grid (documented limitation)")
            }
        }
    }

    func testDurationFrameRoundTrip24fps() {
        let fps = Rational.fps24
        let dur = KTime(seconds: 10.5)
        XCTAssertEqual(fps.frames(in: dur), 252) // 24 * 10.5 = 252
        // 60-frame clip at 24fps -> exactly 2.5s
        XCTAssertEqual(fps.frameStart(60), KTime(seconds: 2.5))
    }

    func testScaledSpeed() {
        let t = KTime(seconds: 4)
        XCTAssertEqual(t.scaled(by: Rational(2, 1)), KTime(seconds: 8))
        XCTAssertEqual(t.scaled(by: Rational(1, 2)), KTime(seconds: 2))
        XCTAssertEqual(t.scaled(by: Rational(1, 3)).milliseconds, 1333.333, accuracy: 0.5)
    }

    func testTimeRangeBasics() {
        let r = TimeRange(start: KTime(seconds: 1), duration: KTime(milliseconds: 500))
        XCTAssertEqual(r.duration, KTime(milliseconds: 500))
        XCTAssertFalse(r.contains(KTime(seconds: 1.5)))
        XCTAssertTrue(r.contains(KTime(seconds: 1.3)))
        XCTAssertTrue(r.intersects(TimeRange(start: KTime(seconds: 1.4), end: KTime(seconds: 2))))
        XCTAssertFalse(r.intersects(TimeRange(start: KTime(seconds: 2), end: KTime(seconds: 3))))
    }
}
