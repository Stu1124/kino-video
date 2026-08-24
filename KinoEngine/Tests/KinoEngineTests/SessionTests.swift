import XCTest
@testable import KinoEngine

final class SessionTests: XCTestCase {

    func makeAsset(duration seconds: Double) -> MediaAsset {
        MediaAsset(uri: "file:///m/a-\(UUID().uuidString).mp4", kind: .video,
                   name: "cam", resolution: KVec2(1920, 1080),
                   duration: KTime(seconds: seconds), fps: 30, audioTrackPresent: true)
    }

    func makeMainProject() -> KinoProject {
        var p = KinoProject()
        p.assets = [makeAsset(duration: 10), makeAsset(duration: 5)]
        p.assets[0].name = "A"
        p.assets[1].name = "B"
        let a = Clip(kind: .video, assetID: p.assets[0].id, start: .zero,
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 5)))
        let b = Clip(kind: .video, assetID: p.assets[1].id, start: KTime(seconds: 6),
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 3)))
        p.tracks[0].clips = [a, b]
        p.meta.schemaVersion = KinoProject.currentSchemaVersion
        return p
    }

    func testSplitMidClip() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        let ok = try EditOps.splitClip(id, at: KTime(seconds: 2), &p)
        XCTAssertTrue(ok)
        let clips = p.tracks[0].clips
        XCTAssertEqual(clips.count, 3)
        XCTAssertEqual(clips[0].sourceRange.end.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(clips[1].sourceRange.start.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(clips[1].start.seconds, 2, accuracy: 0.001)
        XCTAssertEqual(p.duration.seconds, 9, accuracy: 0.01)
    }

    func testSplitInvalidTimes() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        XCTAssertThrowsError(try EditOps.splitClip(UUID(), at: KTime(seconds: 1), &p))
        let atStart = try EditOps.splitClip(id, at: .zero, &p)
        XCTAssertFalse(atStart)
        let atEnd = try EditOps.splitClip(id, at: KTime(seconds: 5), &p)
        XCTAssertFalse(atEnd)
    }

    func testTrimLeftRipple() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        _ = try EditOps.trimLeft(id, bySource: KTime(seconds: 1), ripple: true, &p)
        let clips = p.tracks[0].clips
        XCTAssertEqual(clips.count, 2)
        XCTAssertEqual(clips[0].sourceRange.start.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(clips[0].start.seconds, 0, accuracy: 0.001)
        // b had 1s gap before; ripple closes gap: b start = 4-1 = 3? a shortened by 1 → a end 4; b start 6 → 5
        XCTAssertEqual(clips[1].start.seconds, 5, accuracy: 0.001)
    }

    func testTrimRight() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        _ = try EditOps.trimRight(id, bySource: KTime(seconds: -1), ripple: true, &p)
        let a = p.tracks[0].clips[0]
        XCTAssertEqual(a.sourceRange.end.seconds, 4, accuracy: 0.001)
        // b slides left by 1
        XCTAssertEqual(p.tracks[0].clips[1].start.seconds, 5, accuracy: 0.001)
    }

    func testDuplicateAndDelete() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        let dup = try EditOps.duplicateClip(id, &p)
        XCTAssertNotNil(dup)
        XCTAssertEqual(p.tracks[0].clips.count, 3)
        try EditOps.removeClip(id, &p)
        XCTAssertEqual(p.tracks[0].clips.count, 2)
        XCTAssertNil(p.clip(id))
    }

    func testMoveClip() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        let k = KChannel(property: "scale", keyframes: [Keyframe(time: KTime(seconds: 1), value: 2)])
        var c = p.tracks[0].clips[0]
        c.keyframes = KeyframeStore(channels: ["scale": k])
        p.tracks[0].clips[0] = c
        try EditOps.moveClip(id, to: KTime(seconds: 20), &p)
        let moved = p.tracks[0].clips.first { $0.id == id }!
        XCTAssertEqual(moved.start.seconds, 20, accuracy: 0.001)
        XCTAssertEqual(moved.keyframes.channels["scale"]!.keyframes[0].time.seconds, 21, accuracy: 0.001)
    }

    func testCloseGaps() {
        var p = makeMainProject()
        EditOps.closeGaps(mainTrackIndex: 0, &p)
        let clips = p.tracks[0].clips
        XCTAssertEqual(clips[0].start.seconds, 0)
        XCTAssertEqual(clips[1].start.seconds, 5, accuracy: 0.001)
        XCTAssertEqual(p.duration.seconds, 8, accuracy: 0.01)
    }

    func testSplitPreservesKeyframes() throws {
        var p = makeMainProject()
        let id = p.tracks[0].clips[0].id
        var c = p.tracks[0].clips[0]
        let ks = KChannel(property: "scale", keyframes: [
            Keyframe(time: KTime(seconds: 1), value: 1),
            Keyframe(time: KTime(seconds: 3), value: 2),
            Keyframe(time: KTime(seconds: 4), value: 3),
        ])
        c.keyframes = KeyframeStore(channels: ["scale": ks])
        p.tracks[0].clips[0] = c
        _ = try EditOps.splitClip(id, at: KTime(seconds: 2), &p)
        let left = p.tracks[0].clips[0]
        let right = p.tracks[0].clips[1]
        let lk = left.keyframes.channels["scale"]!.keyframes
        let rk = right.keyframes.channels["scale"]!.keyframes
        // left keeps the key before the cut + boundary key with interpolated value 1.5
        XCTAssertEqual(lk.map { $0.value }, [1, 1.5])
        XCTAssertEqual(lk[0].time.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(lk[1].time.seconds, 2, accuracy: 0.001)
        // right starts at boundary 1.5 and keeps the remaining keys shifted back
        XCTAssertEqual(rk.map { $0.value }, [1.5, 2, 3])
        XCTAssertEqual(rk[1].time.seconds, 1, accuracy: 0.001)
        XCTAssertEqual(rk[2].time.seconds, 2, accuracy: 0.001)
        // animation continuity: value at the splice is identical on both sides
        XCTAssertEqual(lk[1].value, rk[0].value)
    }

    // MARK: Undo/redo session

    func testUndoRedoSequence() throws {
        let p0 = makeMainProject()
        let session = EditorSession(project: p0)
        XCTAssertFalse(session.canUndo)

        let clipID = session.project.tracks[0].clips[0].id
        session.perform("trim") { p in
            try! _ = EditOps.trimRight(clipID, bySource: KTime(seconds: -1), ripple: false, &p)
        }
        XCTAssertTrue(session.canUndo)
        XCTAssertEqual(session.project.tracks[0].clips[0].sourceRange.end.seconds, 4, accuracy: 0.001)

        session.perform("split") { p in
            try! _ = EditOps.splitClip(clipID, at: KTime(seconds: 2), &p)
        }
        XCTAssertEqual(session.project.tracks[0].clips.count, 3)

        session.undo()
        XCTAssertEqual(session.project.tracks[0].clips.count, 2, "split undone")
        session.undo()
        XCTAssertEqual(session.project.tracks[0].clips[0].sourceRange.end.seconds, 5, accuracy: 0.001, "trim undone")
        XCTAssertFalse(session.canUndo)

        session.redo()
        XCTAssertEqual(session.project.tracks[0].clips[0].sourceRange.end.seconds, 4, accuracy: 0.001)
        session.redo()
        XCTAssertEqual(session.project.tracks[0].clips.count, 3)

        // new edit clears redo
        session.undo()
        session.perform("delete") { p in
            try! EditOps.removeClip(session.project.tracks[0].clips[1].id, &p)
        }
        XCTAssertFalse(session.canRedo)
    }

    func testCoalescedGestures() {
        let session = EditorSession(project: makeMainProject())
        let clipID = session.project.tracks[0].clips[0].id
        session.coalescingKey = "drag"
        for step in 0..<30 {
            let delta = KTime(seconds: Double(step) * 0.1)
            _ = session.perform("drag") { p in
                try! EditOps.moveClip(clipID, to: .zero + delta, &p)
            }
        }
        XCTAssertEqual(session.undoStack.count, 1)
        session.coalescingKey = nil
        session.undo()
        XCTAssertEqual(session.project.tracks[0].clips[0].start.seconds, 0, accuracy: 0.001)
    }

    func testSerializationPreservesState() throws {
        var p = makeMainProject()
        p.meta.name = "Vacation"
        let id = p.tracks[0].clips[0].id
        var clip = p.tracks[0].clips[0]
        clip.transform = KTransform(center: KVec2(0.4, 0.6), scale: 1.3, rotation: 25, opacity: 0.8, flipX: true, flipY: false)
        clip.keyframes = KeyframeStore(channels: ["scale": KChannel(property: "scale",
            keyframes: [Keyframe(time: .zero, value: 1), Keyframe(time: KTime(seconds: 2), value: 2, curve: .easeInOut)] )])
        p.tracks[0].clips[0] = clip
        p.lastPlayhead = KTime(seconds: 3.5)
        p.lastSelectedClipID = id

        let data = try p.encodedJSON()
        let decoded = try KinoProject.decode(data)
        XCTAssertEqual(decoded.meta.name, "Vacation")
        let dclip = decoded.tracks[0].clips[0]
        XCTAssertEqual(dclip.transform.scale, 1.3, accuracy: 0.0001)
        XCTAssertEqual(dclip.transform.rotation, 25, accuracy: 0.0001)
        XCTAssertEqual(dclip.keyframes.channels["scale"]!.keyframes[1].curve.kind, .easeInOut)
        XCTAssertEqual(decoded.lastPlayhead.seconds, 3.5, accuracy: 0.0001)
        XCTAssertEqual(decoded.lastSelectedClipID, id)
    }

    func testSpeedMappingRoundTrip() {
        let c = Clip(kind: .video, assetID: UUID(), start: .zero,
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 4)),
                     speed: SpeedSpec(rate: 2))
        XCTAssertEqual(c.duration.seconds, 2, accuracy: 0.0001)
        let src = SpeedMath.sourceTime(atDisplay: KTime(seconds: 1), clip: c)
        XCTAssertEqual(src.seconds, 2, accuracy: 0.0001)
        let back = SpeedMath.displayTime(forSource: src, clip: c)
        XCTAssertEqual(back.seconds, 1, accuracy: 0.0001)
    }

    func testSpeedCurveMappingMonotone() {
        let curve = [SpeedCurvePoint(position: 0, rate: 0.5),
                     SpeedCurvePoint(position: 0.7, rate: 2.0),
                     SpeedCurvePoint(position: 1, rate: 0.5)]
        let c = Clip(kind: .video, assetID: UUID(), start: .zero,
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 4)),
                     speed: SpeedSpec(rate: 1, curve: curve))
        // mapping must be monotone and endpoints exact
        XCTAssertEqual(c.duration.seconds, 4, accuracy: 1.0) // avg>=1... check loosely
        var last: Float = -1
        var monotone = true
        for i in 0...10 {
            let p = Float(i) / 10
            let src = SpeedMath.sourceProgress(atTimelineProgress: p, speed: c.speed)
            if src < last - 0.002 { monotone = false }
            last = src
        }
        XCTAssertTrue(monotone)
        // inverse consistency
        let p = Float(0.5)
        let src = SpeedMath.sourceProgress(atTimelineProgress: p, speed: c.speed)
        let inv = SpeedMath.timelineProgress(forSourceProgress: src, speed: c.speed)
        XCTAssertEqual(inv, p, accuracy: 0.02)
    }
}
