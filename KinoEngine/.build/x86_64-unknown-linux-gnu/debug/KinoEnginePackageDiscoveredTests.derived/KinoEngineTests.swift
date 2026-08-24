import XCTest
@testable import KinoEngineTests

fileprivate extension KTimeTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__KTimeTests = [
        ("testDurationFrameRoundTrip24fps", testDurationFrameRoundTrip24fps),
        ("testExactMulDiv", testExactMulDiv),
        ("testFrameConversion29_97", testFrameConversion29_97),
        ("testFrameStartInversion24fps", testFrameStartInversion24fps),
        ("testFrameStartInversionNTSCWithinOneFrame", testFrameStartInversionNTSCWithinOneFrame),
        ("testFrameStartMonotonicAllRates", testFrameStartMonotonicAllRates),
        ("testRationalReduction", testRationalReduction),
        ("testScaledSpeed", testScaledSpeed),
        ("testTimeRangeBasics", testTimeRangeBasics)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __KinoEngineTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(KTimeTests.__allTests__KTimeTests)
    ]
}