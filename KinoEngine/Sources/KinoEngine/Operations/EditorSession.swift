import Foundation

// MARK: - Change event

public enum EditorEvent: Equatable, Sendable {
    case projectChanged
    case selectionChanged
    case playheadChanged
    case undoRedoChanged(canUndo: Bool, canRedo: Bool)
    case mediaLibraryChanged
    case undoApplied(label: String)
    case redoApplied(label: String)
}

// MARK: - Editor session

/// The editing brain. Owns the canonical project and routes every mutation through
/// labeled undoable changes. UI observes `events`; nothing outside the session
/// may mutate the project directly.
public final class EditorSession {
    public var project: KinoProject
    public private(set) var selectedClipID: UUID?
    public var playhead: KTime { didSet { notify(.playheadChanged) } }

    /// Internal transient pointers used for interaction (move source position of a drag).
    public private(set) var undoStack: [UndoEntry] = []
    public private(set) var redoStack: [UndoEntry] = []
    private var notify: (EditorEvent) -> Void

    /// Coalescing bridge: while a gesture runs, discrete operations are merged.
    public var coalescingKey: String?

    public init(project: KinoProject, notify: @escaping (EditorEvent) -> Void = { _ in }) {
        self.project = project
        self.notify = notify
        self.playhead = project.lastPlayhead
        self.selectedClipID = project.lastSelectedClipID
    }

    // MARK: Selection

    public func select(_ id: UUID?) {
        selectedClipID = id
        notify(.selectionChanged)
    }

    public var selectedClip: Clip? {
        guard let id = selectedClipID else { return nil }
        if let res = project.clip(id) { return res.clip }
        return nil
    }

    public func selectClip(at time: KTime, on trackKind: KTrackKind? = nil) -> Clip? {
        if let kind = trackKind {
            let track = project.tracks.first { $0.kind == kind }
            guard let clip = track?.clips.first(where: { $0.timelineRange.contains(time) }) else { return nil }
            select(clip.id)
            return clip
        }
        var found: Clip?
        var best: KTime = .zero
        for track in project.tracks {
            for clip in track.clips {
                let r = clip.timelineRange
                if r.contains(time) && (found == nil || r.duration.ns > best.ns) {
                    found = clip; best = r.duration
                }
            }
        }
        select(found?.id)
        return found
    }

    // MARK: Undo / redo

    public struct UndoEntry {
        let before: KinoProject
        let after: KinoProject
        let label: String
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Execute and record an undoable change.
    @discardableResult
    public func perform(_ label: String, _ body: (inout KinoProject) -> Void) -> Bool {
        let before = project

        // Commits in a transaction: body may abort leaving project untouched.
        var working = project
        body(&working)
        guard working != project else {
            if let entry = undoStack.last, entry.label == coalescingKey {
                // coalesce — replace latest undo record with the newest state
                undoStack[undoStack.count - 1] = UndoEntry(before: entry.before, after: working, label: label)
            }
            return true // no-op reported but not recorded
        }

        if let key = coalescingKey, let last = undoStack.last, last.label == key {
            undoStack[undoStack.count - 1] = UndoEntry(before: last.before, after: working, label: key)
        } else {
            undoStack.append(UndoEntry(before: before, after: working, label: label))
        }
        redoStack.removeAll()
        project = working
        project.meta.modifiedAt = Date()
        notify(.projectChanged)
        notify(.undoRedoChanged(canUndo: canUndo, canRedo: canRedo))
        return true
    }

    @discardableResult
    public func undo() -> Bool {
        guard let entry = undoStack.popLast() else { return false }
        redoStack.append(entry)
        project = entry.before
        project.meta.modifiedAt = Date()
        // selection may have survived; re-validate
        if let sel = selectedClipID, project.clip(sel) == nil {
            selectedClipID = nil
            notify(.selectionChanged)
        }
        notify(.projectChanged)
        notify(.undoRedoChanged(canUndo: canUndo, canRedo: canRedo))
        notify(.undoApplied(label: entry.label))
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let entry = redoStack.popLast() else { return false }
        undoStack.append(entry)
        project = entry.after
        project.meta.modifiedAt = Date()
        if let sel = selectedClipID, project.clip(sel) == nil {
            selectedClipID = nil
            notify(.selectionChanged)
        }
        notify(.projectChanged)
        notify(.undoRedoChanged(canUndo: canUndo, canRedo: canRedo))
        notify(.redoApplied(label: entry.label))
        return true
    }

    // MARK: Data access and semantics helpers

    public func clip(_ id: UUID) -> (trackIndex: Int, track: Track, clip: Clip)? {
        guard let (ti, clip) = project.clip(id) else { return nil }
        return (ti, project.tracks[ti], clip)
    }

    public func clips(overlapping t: KTime) -> [Clip] {
        project.tracks.flatMap { $0.clips.filter { $0.timelineRange.contains(t) } }
    }

    /// Index of clip on its track sorted by start.
    public func index(ofClip id: UUID) -> Int? {
        guard let c = clip(id) else { return nil }
        return c.track.clips.firstIndex(where: { $0.id == id })
    }
}

// MARK: - Reusable edit helpers (pure functions, fully unit-testable)

public enum EditOps {

    // MARK: Basic clip ops

    public static func addClip(_ clip: Clip, toTrack trackIndex: Int, at start: KTime?, _ p: inout KinoProject) throws {
        guard trackIndex >= 0 && trackIndex < p.tracks.count else { throw EditError.badTrack }
        var c = clip
        if let s = start { c.start = s }
        p.tracks[trackIndex].clips.append(c)
        p.tracks[trackIndex].clips.sort { $0.start.ns < $1.start.ns }
    }

    public static func removeClip(_ id: UUID, _ p: inout KinoProject) throws {
        for ti in p.tracks.indices {
            if let idx = p.tracks[ti].clips.firstIndex(where: { $0.id == id }) {
                p.tracks[ti].clips.remove(at: idx)
                return
            }
        }
        throw EditError.notFound
    }

    /// Split clip at `time` (in-canvas time). If time outside clip range → no-op false.
    /// Speed curves and keyframes are split by remapping times; source ranges split at
    /// the exact source position.
    public static func splitClip(_ id: UUID, at time: KTime, _ p: inout KinoProject) throws -> Bool {
        guard let (ti, _, clip) = locate(id, p) else { throw EditError.notFound }
        let r = clip.timelineRange
        guard time.ns > r.start.ns + 1, time.ns < r.end.ns - 1 else { return false }
        let srcAtSplit = SpeedMath.sourceTime(atDisplay: time - r.start, clip: clip)
        let src0 = TimeRange(start: clip.sourceRange.start, end: srcAtSplit)
        let src1 = TimeRange(start: srcAtSplit, end: clip.sourceRange.end)
        let localCut = time - r.start

        var left = clip
        left.sourceRange = src0
        left.keyframes = Self.keyframesSplit(clip.keyframes, at: localCut, towardLeft: true)
        var right = clip
        right.id = UUID()
        right.start = time
        right.sourceRange = src1
        right.keyframes = Self.keyframesSplit(clip.keyframes, at: localCut, towardLeft: false)

        p.tracks[ti].clips.removeAll { $0.id == id }
        p.tracks[ti].clips.append(left)
        p.tracks[ti].clips.append(right)
        p.tracks[ti].clips.sort { $0.start.ns < $1.start.ns }
        return true
    }

    /// Splits keyframe channels at localCut time. Each child receives its own keys;
    /// a boundary key with the interpolated value is inserted on BOTH sides so the
    /// animation curve remains continuous across the splice.
    static func keyframesSplit(_ store: KeyframeStore, at localCut: KTime, towardLeft: Bool) -> KeyframeStore {
        var out = KeyframeStore(channels: [:])
        let cutValue = (ch: KChannel(property: "_", keyframes: []), v: 0, ok: false)
        _ = cutValue
        for (prop, ch) in store.channels {
            // interpolated value exactly at the cut
            let boundary = ch.evaluate(localCut, defaultValue: 0)
            var ks: [Keyframe] = []
            for k in ch.keyframes {
                if towardLeft && k.time < localCut {
                    ks.append(k)
                } else if !towardLeft && k.time > localCut {
                    ks.append(Keyframe(time: k.time - localCut, value: k.value, curve: k.curve))
                }
            }
            if towardLeft {
                ks.append(Keyframe(time: localCut, value: boundary, curve: .linear))
                ks.sort { $0.time.ns < $1.time.ns }
            } else {
                ks.insert(Keyframe(time: .zero, value: boundary, curve: .hold), at: 0)
                ks.sort { $0.time.ns < $1.time.ns }
                if ks.count > 1 { ks[0].curve = ks[1].curve }
            }
            out.channels[prop] = KChannel(property: prop, keyframes: ks)
        }
        return out
    }

    public static func duplicateClip(_ id: UUID, offset: KTime? = nil, _ p: inout KinoProject) throws -> UUID? {
        guard let (ti, _, clip) = locate(id, p) else { throw EditError.notFound }
        var dup = clip
        dup.id = UUID()
        let gap: KTime = offset ?? KTime(milliseconds: 40)
        // standard placement: right after the original's end
        dup.start = clip.timelineRange.end + gap
        p.tracks[ti].clips.append(dup)
        p.tracks[ti].clips.sort { $0.start.ns < $1.start.ns }
        return dup.id
    }

    /// Move a clip to a new start time on the same track (no collision checks — free placement).
    public static func moveClip(_ id: UUID, to start: KTime, _ p: inout KinoProject) throws {
        guard let (ti, _, clip) = locate(id, p) else { throw EditError.notFound }
        let delta = start - clip.start
        var moved = clip
        moved.start = start
        moved.keyframes = Self.shiftKeys(clip.keyframes, by: delta)
        p.tracks[ti].clips.removeAll { $0.id == id }
        p.tracks[ti].clips.append(moved)
        p.tracks[ti].clips.sort { $0.start.ns < $1.start.ns }
    }

    /// Trim the clip's left edge in source time. If `ripple` is set (main track), clips
    /// after it slide back to close the gap; the trimmed amount goes to the front.
    public static func trimLeft(_ id: UUID, bySource delta: KTime, ripple: Bool, _ p: inout KinoProject) throws -> Bool {
        guard let (ti, _, clip) = locate(id, p) else { throw EditError.notFound }
        let newSourceStart = KTime.min(KTime.max(clip.sourceRange.start + delta, clip.sourceRange.start),
                                       clip.sourceRange.end - KTime(milliseconds: 1))
        let applied = newSourceStart - clip.sourceRange.start
        guard applied.ns != 0 else { return false }

        var updated = clip
        updated.sourceRange.start = newSourceStart
        updated.keyframes = Self.trimKeysStart(clip.keyframes, removedSource: applied, clip: clip)
        if ripple {
            let displayDelta = SpeedMath.sourceToDisplay(applied, speed: clip.speed)
            let isFirst = p.tracks[ti].clips.filter { $0.start.ns < clip.start.ns }.isEmpty
            // rippled first clip keeps its position; otherwise the edge slides right
            // and following clips close the gap.
            if !isFirst {
                updated.start = clip.start + displayDelta
                updated.keyframes = Self.shiftKeys(updated.keyframes, by: displayDelta)
            }
            for i in p.tracks[ti].clips.indices {
                var c = p.tracks[ti].clips[i]
                if c.id != id && c.start.ns >= clip.timelineRange.end.ns {
                    c.start = c.start - displayDelta
                    c.keyframes = Self.shiftKeys(c.keyframes, by: KTime(ns: -displayDelta.ns))
                    p.tracks[ti].clips[i] = c
                }
            }
        }
        if let idx = p.tracks[ti].clips.firstIndex(where: { $0.id == id }) {
            p.tracks[ti].clips[idx] = updated
        }
        p.tracks[ti].clips.sort { $0.start.ns < $1.start.ns }
        return true
    }

    /// Trim the clip's right edge in source time; `ripple` closes the following gap.
    public static func trimRight(_ id: UUID, bySource delta: KTime, ripple: Bool, _ p: inout KinoProject) throws -> Bool {
        guard let (ti, _, clip) = locate(id, p) else { throw EditError.notFound }
        let newSourceEnd = KTime.min(KTime.max(clip.sourceRange.end + delta, clip.sourceRange.start + KTime(milliseconds: 1)),
                                     clip.sourceRange.end)
        let applied = newSourceEnd - clip.sourceRange.end
        guard applied.ns != 0 else { return false }

        var updated = clip
        updated.sourceRange.end = newSourceEnd
        updated.keyframes = Self.trimKeysEnd(clip.keyframes, removedSource: KTime(ns: -applied.ns), clip: clip)
        if ripple {
            let displayDelta = SpeedMath.sourceToDisplay(applied, speed: clip.speed)
            for i in p.tracks[ti].clips.indices {
                var c = p.tracks[ti].clips[i]
                if c.start.ns >= clip.timelineRange.end.ns {
                    c.start = c.start + displayDelta
                    c.keyframes = Self.shiftKeys(c.keyframes, by: displayDelta)
                    p.tracks[ti].clips[i] = c
                }
            }
        }
        if let idx = p.tracks[ti].clips.firstIndex(where: { $0.id == id }) {
            p.tracks[ti].clips[idx] = updated
        }
        return true
    }

    // MARK: Keyframe helpers

    static func shiftKeys(_ store: KeyframeStore, by delta: KTime) -> KeyframeStore {
        var out = KeyframeStore(channels: [:])
        for (prop, ch) in store.channels {
            out.channels[prop] = KChannel(property: prop, keyframes: ch.keyframes.map {
                Keyframe(time: $0.time + delta, value: $0.value, curve: $0.curve)
            })
        }
        return out
    }

    static func trimKeysStart(_ store: KeyframeStore, removedSource: KTime, clip: Clip) -> KeyframeStore {
        guard removedSource.ns > 0 else { return store }
        let displayCut = SpeedMath.sourceToDisplay(removedSource, speed: clip.speed)
        var out = KeyframeStore(channels: [:])
        for (prop, ch) in store.channels {
            var ks: [Keyframe] = []
            for k in ch.keyframes where k.time >= displayCut {
                ks.append(Keyframe(time: k.time - displayCut, value: k.value, curve: k.curve))
            }
            out.channels[prop] = KChannel(property: prop, keyframes: ks)
        }
        return out
    }

    static func trimKeysEnd(_ store: KeyframeStore, removedSource: KTime, clip: Clip) -> KeyframeStore {
        guard removedSource.ns > 0 else { return store }
        let displayTrim = SpeedMath.sourceToDisplay(removedSource, speed: clip.speed)
        let newLen = clip.duration - displayTrim
        var out = KeyframeStore(channels: [:])
        for (prop, ch) in store.channels {
            out.channels[prop] = KChannel(property: prop, keyframes: ch.keyframes.filter { $0.time < newLen })
        }
        return out
    }

    // MARK: Utility

    static func locate(_ id: UUID, _ p: KinoProject) -> (Int, Track, Clip)? {
        for (ti, track) in p.tracks.enumerated() {
            if let c = track.clips.first(where: { $0.id == id }) { return (ti, track, c) }
        }
        return nil
    }

    /// Auto-collapse gaps between adjacent clips on the main track (ripple delete style).
    public static func closeGaps(mainTrackIndex: Int, _ p: inout KinoProject) {
        guard mainTrackIndex < p.tracks.count else { return }
        let clips = p.tracks[mainTrackIndex].clips.sorted { $0.start.ns < $1.start.ns }
        if clips.isEmpty { return }
        let firstStart = clips[0].start
        var current = firstStart
        var fixed: [Clip] = []
        fixed.reserveCapacity(clips.count)
        for var c in clips {
            if c.start.ns != current.ns {
                let delta = current - c.start
                c.keyframes = Self.shiftKeys(c.keyframes, by: delta)
                c.start = current
            }
            fixed.append(c)
            current = c.timelineRange.end
        }
        p.tracks[mainTrackIndex].clips = fixed
    }

    /// Auto-slice an asset of duration D into clips of wallclock <= maxChunk starting at start.
    public static func sliceMediaIntoClips(assetID: UUID, sourceDuration: KTime, start: KTime, maxChunk: KTime? = nil) -> [Clip] {
        let chunk = maxChunk ?? KTime(seconds: 30)
        guard sourceDuration.ns > 0 else { return [] }
        var clips: [Clip] = []
        var t = KTime.zero
        while t < sourceDuration {
            let end = KTime.min(t + chunk, sourceDuration)
            clips.append(Clip(
                kind: .video,
                assetID: assetID,
                start: start + t,
                sourceRange: TimeRange(start: t, end: end)))
            t = end
        }
        return clips
    }
}

public enum EditError: Error, Equatable {
    case notFound
    case badTrack
    case outOfRange
}
