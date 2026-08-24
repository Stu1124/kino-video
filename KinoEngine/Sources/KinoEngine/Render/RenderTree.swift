import Foundation

// MARK: - Fully-evaluated layer state at an instant

/// One resolved visual layer. The iOS renderer consumes these per frame, so
/// the preview and the exporter are driven by identical math — the core
/// WYSIWYG guarantee.
public struct LayerFrame: Hashable, Codable, Sendable {
    public var clipID: UUID
    public var kind: KClipKind
    public var assetID: UUID?
    /// Raster dimensions of the source (video/image assets) in pixels.
    public var assetSize: KVec2?
    /// Normalized crop rect (defaults to full source) for fit math.
    public var cropRect: KCropRect?
    /// Source time to decode (speed/reverse applied, in asset time).
    public var sourceTime: KTime
    /// Local progress [0..1] through clip (animations use it).
    public var progress: Float
    /// Resolved transform (keyframes + animation presets already baked in).
    public var transform: KTransform
    /// Color adjustments (filter) resolved at this instant.
    public var adjustments: ColorAdjust
    /// Effect stack: spec id + resolved parameter values.
    public var effects: [ResolvedEffect]
    public var masks: [MaskSpec]
    /// Chroma key spec when the clip is dual-keyed.
    public var chromaKey: ChromaKeySpec?
    /// Background removal strength (0 = none, 1 = full cutout).
    public var cutout: Float
    /// Text layer content (static text; evaluates fonts at render time).
    public var text: TextContent?
    /// Sticker content (atlas lookup at render time).
    public var sticker: StickerContent?
    /// Sound: volume gain at this instant (0..2).
    public var gain: Float
}

public struct ResolvedEffect: Hashable, Codable, Sendable {
    public var specID: String
    public var strength: Float
    public var params: [String: Float]
    public init(specID: String, strength: Float, params: [String: Float]) {
        self.specID = specID; self.strength = strength; self.params = params
    }
}

// MARK: - Animation preset catalogue (original Kino presets)

public struct KinoAnimationPreset: Hashable, Codable, Sendable {
    public var id: String
    public var name: String
    public var phase: AnimationRef.Phase
    /// Duration class: how long the animation takes relative to clip (0..1 fraction kept open)
    public var ease: KCurveKind

    public init(id: String, name: String, phase: AnimationRef.Phase, ease: KCurveKind = .easeOut) {
        self.id = id
        self.name = name
        self.phase = phase
        self.ease = ease
    }

    /// Evaluate a transform delta for progress p in [0..1] (0 = start of animation).
    public func delta(at p: Float, base: KTransform) -> KTransform {
        let curve = KCurveSpec(kind: ease)
        let e = curve.eased(min(1, max(0, p)))
        var t = base
        let opacity: Float
        var scale: Float = 1
        var rotation: Float = 0
        var offset = KVec2(0, 0)

        switch id {
        case "kino.fade":
            opacity = e
        case "kino.fade.up":
            opacity = e
            offset.y = -(1 - e) * 0.18
        case "kino.slide.left":
            offset.x = (1 - e) * 0.7
            opacity = e
        case "kino.slide.right":
            offset.x = -(1 - e) * 0.7
            opacity = e
        case "kino.zoom.pop":
            opacity = e < 0.99 ? e : 1
            scale = 0.2 + 0.8 * Swift.min(1, e * 1.6)
        case "kino.zoom.slow":
            opacity = e
            scale = 0.9 + 0.1 * e
        case "kino.rotate.in":
            opacity = e
            rotation = (1 - e) * -90
        case "kino.swing.loop":
            // looping? entrance/slide handled externally; swing adds gentle oscillation
            opacity = 1
            rotation = sin(e * .pi * 3) * 6
        case "kino.bounce.loop":
            opacity = 1
            scale = 1 + max(0, sin(e * .pi * 4)) * 0.12
        case "kino.pulse.loop":
            opacity = 0.86 + 0.14 * sin(e * .pi * 4)
        case "kino.flash.loop":
            opacity = 0.4 + 0.6 * sin(e * .pi * 3)
        default:
            opacity = e
        }

        // exit phases play the same shapes backwards
        let mirrored = phase == .exit
        let pe = mirrored ? (1 - e) : e
        _ = pe
        t.opacity *= opacity
        t.scale *= scale
        t.rotation += rotation
        let off = mirrored ? offset * -1 : offset
        _ = off
        t.center = t.center + offset
        return t
    }
}

public enum AnimationLibrary {
    public static let presets: [KinoAnimationPreset] = {
        func p(_ id: String, _ name: String, _ phase: AnimationRef.Phase, _ ease: KCurveKind = .easeOut) -> KinoAnimationPreset {
            KinoAnimationPreset(id: "kino.\(id)", name: name, phase: phase, ease: ease)
        }
        let all: [KinoAnimationPreset] = [
            p("fade", "Fade", .entrance, .easeInOut),
            p("fade.up", "Rise", .entrance, .easeOut),
            p("slide.left", "Slide In", .entrance),
            p("slide.right", "Slide Out", .entrance),
            p("zoom.pop", "Pop", .entrance, .easeOut),
            p("zoom.slow", "Swoop", .entrance, .easeInOut),
            p("rotate.in", "Tumble", .entrance, .easeOut),
        ]
        let exit = all.filter { $0.name != "Rise" }.map { a -> KinoAnimationPreset in
            KinoAnimationPreset(id: a.id + ".out", name: a.name + " Out", phase: .exit, ease: a.ease)
        }
        let loops: [KinoAnimationPreset] = [
            p("swing.loop", "Swing", .looped, .easeInOut),
            p("bounce.loop", "Bounce", .looped, .easeInOut),
            p("pulse.loop", "Pulse", .looped, .easeInOut),
            p("flash.loop", "Flash", .looped, .easeInOut),
        ]
        return all + exit + loops
    }()
}

// MARK: - Render tree evaluation

public enum RenderTree {

    /// Evaluate all visible layers at canvas time t, ordered bottom (background) → top.
    public static func layers(at t: KTime, project: KinoProject) -> [LayerFrame] {
        var out: [LayerFrame] = []
        for track in project.tracks {
            if track.isHidden { continue }
            for clip in track.clips {
                let r = clip.timelineRange
                if !r.contains(t) { continue }
                out.append(Self.frame(for: clip, at: t, assetSize: Self.mediaSizeProvider, project: project))
            }
        }
        // ordering: tracks bottom→top as stored; upper KTrackKinds already above main by list order.
        return out
    }

    /// Resolved media size for a clip asset (project-dependent; injectable for testability).
    public static var mediaSizeProvider: ((UUID, KinoProject) -> KVec2?) = { _, _ in nil }

    public static func frame(for clip: Clip, at t: KTime, assetSize provider: ((UUID, KinoProject) -> KVec2?)? = nil, project: KinoProject? = nil) -> LayerFrame {
        let local = t - clip.start
        let assetSize = provider.flatMap { p in clip.assetID.flatMap { p($0, project!) } }
        let cropRect = clip.transform.crop
        let progress = clip.duration.ns > 0 ? Float(local.ns) / Float(clip.duration.ns) : 0

        // 1. keyframe evaluation: x, y, scale, rotation, opacity channels
        let keyed = clip.keyframes.evaluateAll(local)
        var center = clip.transform.center
        if let x = keyed["x"] { center.x = x }
        if let y = keyed["y"] { center.y = y }
        var transform = clip.transform
        if let s = keyed["scale"] { transform.scale = s }
        if let r = keyed["rotation"] { transform.rotation = r }
        if let o = keyed["opacity"] { transform.opacity = o }
        transform.center = center

        // 2. animation presets
        if let anim = clip.animation {
            let durNs = anim.duration.ns
            let localNs = local.ns
            if localNs < durNs || anim.phase == .looped {
                let p = durNs > 0 ? Float(localNs) / Float(durNs) : 1
                if let preset = AnimationLibrary.presets.first(where: { $0.id == anim.presetID }) {
                    transform = preset.delta(at: p, base: transform)
                }
            }
        }

        // 3. source time for raster decode
        let srcRelative = SpeedMath.sourceTime(atDisplay: local, clip: clip)
        let srcRange = clip.sourceRange
        let srcT: KTime
        if clip.speed.reversed {
            srcT = srcRange.end - (srcRelative - srcRange.start)
        } else {
            srcT = srcRelative
        }

        // 4. audio gain
        let gain = clip.kind == .video || clip.kind == .audio ? clip.audio.gain(progress: progress) : 0

        // 5. resolved filters/effects with keyframe support on effect params via prefixed channels
        let adjustments = clip.filter?.adjustments ?? .neutral
        var effects: [ResolvedEffect] = []
        for e in clip.effects {
            var params: [String: Float] = [:]
            for (k, v) in e.values {
                params[k] = keyed["fx.\(e.specID).\(k)"] ?? v
            }
            var strength = e.strength
            if let s = keyed["fx.\(e.specID)"] { strength = s }
            effects.append(ResolvedEffect(specID: e.specID, strength: strength, params: params))
        }

        return LayerFrame(clipID: clip.id, kind: clip.kind, assetID: clip.assetID,
                          assetSize: assetSize, cropRect: cropRect,
                          sourceTime: srcT, progress: progress,
                          transform: transform, adjustments: adjustments,
                          effects: effects, masks: clip.masks,
                          chromaKey: nil, cutout: 0,
                          text: clip.text, sticker: clip.sticker, gain: gain)
    }
}
