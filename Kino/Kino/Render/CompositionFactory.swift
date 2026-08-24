import AVFoundation
import Foundation
import KinoEngine

/// Builds the AVFoundation objects that drive the editor:
///  - an AVComposition of media (main + overlay video clips), a single clock
///    video track and audio tracks;
///  - an AVVideoComposition whose custom compositor renders project state;
///  - an AVAudioMix carrying mix parameters (volumes/fades/mutes).
///
/// The clock track is only there to advance time — every frame rendered by
/// KinoCompositor comes from the project snapshot inside the instruction.
final class CompositionFactory {

    struct Model {
        let asset: AVComposition
        let videoComposition: AVMutableVideoComposition
        let audioMix: AVMutableAudioMix
        let clockTrackID: CMPersistentTrackID
    }

    /// Build composition for preview/export at a given scale (renderSize = canvas * scale).
    static func build(project: KinoProject, renderScale: Float, fps: Rational = .fps30) throws -> Model {
        return try buildSync(project: project, renderScale: renderScale, fps: fps)
    }

    static func buildSync(project: KinoProject, renderScale: Float, fps: Rational = .fps30) throws -> Model {
        let composition = AVMutableComposition()

        // ---- clock video track (main+overlay video clips; images/text skipped) ----
        let clockTrack = composition.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
        let clockID = clockTrack.trackID

        for track in project.tracks {
            guard track.kind == .main || track.kind == .overlay else { continue }
            for clip in track.clips {
                guard clip.kind == .video, let assetID = clip.assetID,
                      let asset = project.asset(assetID), let url = URL(string: asset.uri) else { continue }
                let src = AVURLAsset(url: url)
                guard let srcTrack = try? SynchronousTrackLoader.track(asset: src, type: .video) else { continue }
                let srcRange = CMTimeRange(start: clip.sourceRange.start.cmTime, duration: clip.sourceRange.duration.cmTime)
                _ = try? clockTrack.insertTimeRange(srcRange, of: srcTrack, at: clip.start.cmTime)
            }
        }
        // compose the clock track's natural size
        let vSize = project.canvas.renderSize

        // ---- audio composition ----
        let audioTrack = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
        for track in project.tracks {
            for clip in track.clips {
                guard clip.kind == .video || clip.kind == .audio else { continue }
                guard let assetID = clip.assetID, let url = URL(string: project.asset(assetID)?.uri ?? "") else { continue }
                let src = AVURLAsset(url: url)
                guard let srcAudio = try? SynchronousTrackLoader.track(asset: src, type: .audio) else { continue }
                let srcStart = clip.sourceRange.start.cmTime
                let srcDur = clip.sourceRange.duration.cmTime
                let at = clip.start.cmTime + clip.audio.offset.cmTime
                _ = try? audioTrack.insertTimeRange(CMTimeRange(start: srcStart, duration: srcDur), of: srcAudio, at: at)
            }
        }

        // ---- event boundaries ----
        var boundaries: Set<Int64> = [0]
        for track in project.tracks {
            for clip in track.clips {
                boundaries.insert(clip.start.ns)
                boundaries.insert(clip.timelineRange.end.ns)
                if let transition = clip.transition {
                    boundaries.insert(clip.timelineRange.end.ns - transition.duration.ns)
                }
            }
        }
        let sorted = boundaries.sorted().map { KTime(ns: $0) }
        let duration = project.duration
        let totalNs = max(1, duration.ns)

        // ---- instructions ----
        let videoComp = AVMutableVideoComposition()
        videoComp.customVideoCompositorClass = KinoCompositor.self
        videoComp.renderSize = CGSize(width: CGFloat(vSize.x) * CGFloat(renderScale),
                                      height: CGFloat(vSize.y) * CGFloat(renderScale))
        videoComp.frameDuration = CMTime(value: 1, timescale: CMTimeScale(fps.den * Int64(max(1, fps.num / max(fps.den, 1)))))
        // frame duration = 1/fps exact rational
        let frameDurUnits: Int64 = fps.num
        let frameDurScale: Int64 = fps.den
        videoComp.frameDuration = CMTime(value: CMTimeValue(frameDurScale), timescale: CMTimeScale(frameDurUnits * 1))

        var instructions: [KinoRenderInstruction] = []
        for i in 0..<max(1, sorted.count - 1) {
            let s = sorted[i].cmTime
            let e = min(KTime(ns: totalNs), sorted[i + 1]).cmTime
            if e <= s { continue }
            let payload = slicePayload(project: project,
                                       renderSize: videoComp.renderSize,
                                       from: KTime(s), to: KTime(e),
                                       clockID: clockID)
            instructions.append(KinoRenderInstruction(timeRange: CMTimeRange(start: s, end: e), payload: payload))
        }
        // ensure the last slice extends to full duration
        if let lastTime = sorted.last, lastTime.ns < totalNs {
            let payload = slicePayload(project: project,
                                       renderSize: videoComp.renderSize,
                                       from: lastTime, to: KTime(ns: totalNs),
                                       clockID: clockID)
            instructions.append(KinoRenderInstruction(
                timeRange: CMTimeRange(start: lastTime.cmTime, duration: (KTime(ns: totalNs) - lastTime).cmTime),
                payload: payload))
        }
        videoComp.instructions = instructions

        // ---- audio mix ----
        let mix = AVMutableAudioMix()
        var params: [AVAudioMixInputParameters] = []
        for (trackInd, clip) in audioClips(project: project).enumerated() {
            let p = AVMutableAudioMixInputParameters(track: audioTrack)
            let start = clip.start.cmTime
            let end = (clip.start + clip.duration).cmTime
            let av = Float(clip.audio.muted ? 0 : clip.audio.volume)
            p.setVolume(av, at: start)
            p.setVolumeRamp(fromStartVolume: 0, toEndVolume: av, timeRange: CMTimeRange(start: start, duration: clip.audio.fadeIn.cmTime))
            if clip.audio.fadeOut.ns > 0 {
                let fadeStart = end - clip.audio.fadeOut.cmTime
                p.setVolumeRamp(fromStartVolume: av, toEndVolume: 0, timeRange: CMTimeRange(start: fadeStart, end: end))
            }
            p.audioTimePitchAlgorithm = clip.speed.preservePitch ? .timeDomain : .spectral
            params.append(p)
            _ = trackInd
        }
        mix.inputParameters = params

        return Model(asset: composition,
                     videoComposition: videoComp,
                     audioMix: mix,
                     clockTrackID: clockID)
    }

    static func audioClips(project: KinoProject) -> [Clip] {
        project.tracks.flatMap { $0.clips }.filter {
            $0.kind == .audio || ($0.kind == .video && ($0.assetID != nil))
        }
    }

    /// Which transition applies at this time slice's boundary (if any).
    static func transition(at time: KTime, project: KinoProject) -> KinoTransition.Resolved? {
        for track in project.tracks {
            for clip in track.clips {
                if let t = clip.transition {
                    let boundary = clip.timelineRange.end
                    if time >= boundary - t.duration && time <= boundary {
                        let dir: Float = t.direction
                        return KinoTransition.Resolved(kind: KinoTransition.Kind(rawValue: t.kind) ?? .dissolve, duration: t.duration, direction: dir)
                    }
                }
            }
        }
        return nil
    }

    private static func slicePayload(project: KinoProject, renderSize: CGSize,
                                     from: KTime, to: KTime, clockID: CMPersistentTrackID) -> KinoSlicePayload {
        var transition: KinoTransition.Resolved?
        var leftID: UUID?
        var rightID: UUID?
        var boundary: KTime?
        for track in project.tracks {
            guard track.kind == .main else { continue }
            for clip in track.clips {
                if let t = clip.transition {
                    let b = clip.timelineRange.end
                    if to > (b - t.duration) && from < b {
                        transition = KinoTransition.Resolved(kind: KinoTransition.Kind(rawValue: t.kind) ?? .dissolve,
                                                            duration: t.duration, direction: t.direction)
                        leftID = clip.id
                        boundary = b
                        // right neighbor
                        let neighbor = track.clips
                            .filter { $0.start.ns >= b.ns - 1 }
                            .sorted { $0.start.ns < $1.start.ns }.first
                        rightID = neighbor?.id
                    }
                }
            }
        }
        return KinoSlicePayload(project: project, renderSizePx: renderSize,
                                background: project.canvas.background,
                                transition: transition,
                                transitionLeftID: leftID,
                                transitionRightID: rightID,
                                transitionBoundary: boundary,
                                clockTrackID: clockID)
    }
}


/// Synchronous AVAsset track loader (deprecated-but-safe) for composition building.
enum SynchronousTrackLoader {
    static func track(asset: AVURLAsset, type: AVMediaType) throws -> AVAssetTrack {
        let semaphore = DispatchSemaphore(value: 0)
        var found: AVAssetTrack?
        var error: Error?
        asset.loadTracks(withMediaType: type) { tracks, err in
            found = tracks?.first
            error = err
            semaphore.signal()
        }
        semaphore.wait()
        if let error { throw error }
        guard let found else { throw NSError(domain: "kino.sync", code: 1) }
        return found
    }
}
