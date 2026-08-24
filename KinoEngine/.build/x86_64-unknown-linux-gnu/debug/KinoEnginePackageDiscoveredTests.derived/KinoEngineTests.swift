import XCTest
@testable import KinoEngineTests

fileprivate extension AudioDSPTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__AudioDSPTests = [
        ("testAudioMath", testAudioMath),
        ("testBeatGridAndSnap", testBeatGridAndSnap),
        ("testDominantInterval", testDominantInterval),
        ("testEnvelope", testEnvelope),
        ("testOnsetDetectionClicks", testOnsetDetectionClicks),
        ("testSilenceDetection", testSilenceDetection),
        ("testWaveformBucketCount", testWaveformBucketCount),
        ("testWaveformSilence", testWaveformSilence)
    ]
}

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

fileprivate extension SessionTests {
    @available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
    static nonisolated(unsafe) let __allTests__SessionTests = [
        ("testCloseGaps", testCloseGaps),
        ("testCoalescedGestures", testCoalescedGestures),
        ("testDuplicateAndDelete", testDuplicateAndDelete),
        ("testMoveClip", testMoveClip),
        ("testSerializationPreservesState", testSerializationPreservesState),
        ("testSpeedCurveMappingMonotone", testSpeedCurveMappingMonotone),
        ("testSpeedMappingRoundTrip", testSpeedMappingRoundTrip),
        ("testSplitInvalidTimes", testSplitInvalidTimes),
        ("testSplitMidClip", testSplitMidClip),
        ("testSplitPreservesKeyframes", testSplitPreservesKeyframes),
        ("testTrimLeftRipple", testTrimLeftRipple),
        ("testTrimRight", testTrimRight),
        ("testUndoRedoSequence", testUndoRedoSequence)
    ]
}
@available(*, deprecated, message: "Not actually deprecated. Marked as deprecated to allow inclusion of deprecated tests (which test deprecated functionality) without warnings")
func __KinoEngineTests__allTests() -> [XCTestCaseEntry] {
    return [
        testCase(AudioDSPTests.__allTests__AudioDSPTests),
        testCase(KTimeTests.__allTests__KTimeTests),
        testCase(SessionTests.__allTests__SessionTests)
    ]
}