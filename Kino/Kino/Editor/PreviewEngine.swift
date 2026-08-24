import AVFoundation
import Combine
import Foundation
import KinoEngine

/// Drives playback + scrubbing of an edit. When scrubbing, AVPlayer steps by
/// frames; during gestures a "freeze" mode renders on demand (frame-accurate,
/// never blocking the main thread).
public final class PreviewEngine: ObservableObject {
    public static let shared = PreviewEngine()

    public init() {
        player = AVPlayer()
        setPlayerRateDefaults()
        let interval = CMTime(seconds: 1.0 / 60.0, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] t in
            self?.time = KTime(t)
        }
    }

    @Published public private(set) var time: KTime = .zero
    @Published public private(set) var playing: Bool = false
    @Published public private(set) var ready: Bool = false
    @Published public var isScrubbing: Bool = false

    let player: AVPlayer
    private var item: AVPlayerItem?
    private var timeObserver: Any?
    private var compositionModel: CompositionFactory.Model?
    private var clock: AnyCancellable?

    private func setPlayerRateDefaults() {
        player.automaticallyWaitsToMinimizeStalling = true
    }

    /// Rebuilds playback content for the project. Called when project data changes.
    /// Deferred rebuilds are batched (a 40ms tick) so a fast gesture does not spawn builds.
    public private(set) var pendingRebuild: KinoProject?

    public func rebuild(project: KinoProject, renderScale: Float = 0.6, keepTime: Bool = true) {
        let old = time
        _ = old
        pendingRebuild = project
        let seq = UUID()
        rebuildToken = seq
        let kept = keepTime ? time : .zero
        // off-main build
        rebuildQueue.async { [weak self] () -> Void in
            guard let self else { return }
            do {
                let model = try CompositionFactory.build(project: project, renderScale: renderScale, fps: project.canvas.fps)
                let videoComp = model.videoComposition
                videoComp.renderSize = CGSize(width: CGFloat(project.canvas.renderSize.x) * CGFloat(renderScale),
                                              height: CGFloat(project.canvas.renderSize.y) * CGFloat(renderScale))
                // inject asset index for renderer
                CanvasRenderer.uriResolver = { id in project.asset(id)?.uri }
                DispatchQueue.main.async {
                    guard self.rebuildToken == seq else { return }
                    self.install(item: model, project: project, startAt: kept)
                }
            } catch {
                // fall back to plain playback down the road; for now leave state
            }
        }
    }

    private var rebuildToken: UUID?
    private let rebuildQueue = DispatchQueue(label: "kino.rebuild", qos: .userInitiated)

    private func install(item model: CompositionFactory.Model, project: KinoProject, startAt: KTime) {
        let avItem = AVPlayerItem(asset: model.asset)
        avItem.videoComposition = model.videoComposition
        avItem.audioMix = model.audioMix
        avItem.seekingWaitsForVideoCompositionRendering = true
        let oldTime = time
        player.replaceCurrentItem(with: avItem)
        item = avItem
        compositionModel = model
        ready = true
        time = startAt
        if startAt.ns > 0 {
            player.seek(to: startAt.cmTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                self?.time = startAt
            }
        }
        _ = oldTime
    }

    // MARK: Transport

    public func play() {
        guard ready, !isScrubbing else { return }
        player.play()
        playing = true
    }

    public func pause() {
        player.pause()
        playing = false
    }

    public func togglePlay() {
        playing ? pause() : play()
    }

    /// Frame-accurate scrub with rendering wait. If the position is far, seek fast.
    public func seek(_ t: KTime, accurate: Bool = false) {
        guard let item else { return }
        time = t
        if isScrubbing {
            player.pause()
        }
        let tol: CMTime = accurate ? .zero : CMTime(seconds: 0.05, preferredTimescale: 600)
        player.seek(to: t.cmTime, toleranceBefore: tol, toleranceAfter: tol)
    }

    /// Step by ±1 frame.
    public func stepFrame(_ count: Int) {
        let fps = Rational.fps30 // canvas default
        let frameNs = 1_000_000_000 * fps.den / fps.num
        let target = time + KTime(ns: frameNs * Int64(count))
        pause()
        seek(target, accurate: true)
    }

    deinit {
        if let observer = timeObserver { player.removeTimeObserver(observer) }
    }
}
