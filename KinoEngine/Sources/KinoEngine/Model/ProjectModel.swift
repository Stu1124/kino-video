import Foundation

// MARK: - Media assets

public enum KMediaKind: String, Codable, Sendable {
    case video
    case image
    case audio
    case generated // e.g. TTS/voice-over produced by the app
}

/// Project-level reference to a source asset. Assets are immutable — edits never touch them.
public struct MediaAsset: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var uri: String
    public var kind: KMediaKind
    public var name: String

    public var resolution: KVec2?
    public var duration: KTime?
    /// Nominal fps when known.
    public var fps: Float?
    public var audioTrackPresent: Bool
    /// Date added for sorting.
    public var addedAt: Date

    public init(id: UUID = UUID(),
                uri: String,
                kind: KMediaKind,
                name: String,
                resolution: KVec2? = nil,
                duration: KTime? = nil,
                fps: Float? = nil,
                audioTrackPresent: Bool = false,
                addedAt: Date = Date()) {
        self.id = id
        self.uri = uri
        self.kind = kind
        self.name = name
        self.resolution = resolution
        self.duration = duration
        self.fps = fps
        self.audioTrackPresent = audioTrackPresent
        self.addedAt = addedAt
    }
}

// MARK: - Clips

public enum KClipKind: String, Codable, Sendable {
    case video
    case image
    case audio
    case text
    case sticker
}

/// How a source range maps into timeline time (speed).
public struct SpeedSpec: Hashable, Codable, Sendable {
    /// Constant speed multiplier (1 = normal). 0.5 = half speed.
    public var rate: Float
    /// Play source in reverse.
    public var reversed: Bool
    /// Preserve pitch when rate != 1 (audio only).
    public var preservePitch: Bool
    /// Optional piecewise speed curve (rate over normalized source progress).
    /// When nil, a constant `rate` is used.
    public var curve: [SpeedCurvePoint]

    public init(rate: Float = 1, reversed: Bool = false, preservePitch: Bool = true, curve: [SpeedCurvePoint] = []) {
        self.rate = rate
        self.reversed = reversed
        self.preservePitch = preservePitch
        self.curve = curve
    }
}

public struct SpeedCurvePoint: Hashable, Codable, Sendable {
    /// 0..1 normalized position along the *timeline* duration of the clip.
    public var position: Float
    /// rate multiplier at this point (clipped into 0.02..8).
    public var rate: Float
    public init(position: Float, rate: Float) {
        self.position = min(1, max(0, position))
        self.rate = min(8, max(0.02, rate))
    }
}

/// Audio controls for a video clip's embedded audio or an audio clip.
public struct AudioSpec: Hashable, Codable, Sendable {
    public var volume: Float        // 0..2 (amplification allowed up to 2x)
    public var muted: Bool
    public var fadeIn: KTime
    public var fadeOut: KTime
    /// Nudge vs video: audio plays this offset ahead/behind.
    public var offset: KTime
    public var allowPitchCorrection: Bool

    public init(volume: Float = 1, muted: Bool = false,
                fadeIn: KTime = .zero, fadeOut: KTime = .zero,
                offset: KTime = .zero, allowPitchCorrection: Bool = true) {
        self.volume = volume
        self.muted = muted
        self.fadeIn = fadeIn
        self.fadeOut = fadeOut
        self.offset = offset
        self.allowPitchCorrection = allowPitchCorrection
    }

    /// Gain multiplier at normalized local clip time [0..1] (fade+volume, not mute).
    public func gain(progress p: Float) -> Float {
        guard !muted else { return 0 }
        var g = volume
        let fi = Float(fadeIn.seconds)
        let fo = Float(fadeOut.seconds)
        let total = Float(p * 0.0) // placeholder to keep signature stable
        _ = total
        if fi > 0 && p < fi { g *= p / fi }
        if fo > 0 && p > 1 - fo { g *= (1 - p) / fo }
        return min(2, max(0, g))
    }
}

/// A text layer's content & typography.
public struct TextContent: Hashable, Codable, Sendable {
    public var string: String
    public var fontName: String            // resolved by the app; known fonts registry
    public var fontSize: Float             // canvas-normalized (fraction of canvas height)
    public var fontWeight: Float           // 0..1 width of medium → bold by platform mapping
    public var colorHex: UInt32
    public var opacity: Float
    public var alignment: Int              // 0 left, 1 center, 2 right
    public var strokeColorHex: UInt32?
    public var strokeWidth: Float          // canvas-normalized
    public var shadow: Bool
    public var shadowColorHex: UInt32?
    public var shadowRadius: Float
    public var backgroundColorHex: UInt32?
    public var backgroundPadding: Float
    public var letterSpacing: Float        // 0..1 em fraction
    public var lineSpacing: Float          // em fraction
    public var uppercase: Bool
    public var curvedPath: [KVec2]?        // optional arc/curve lettering (empty = none)

    public static let defaultStyle = TextContent(
        string: "Text",
        fontName: "Default",
        fontSize: 0.07,
        fontWeight: 0.5,
        colorHex: 0xFFFFFFFF,
        opacity: 1,
        alignment: 1,
        strokeColorHex: nil,
        strokeWidth: 0,
        shadow: false,
        shadowColorHex: nil,
        shadowRadius: 0,
        backgroundColorHex: nil,
        backgroundPadding: 0,
        letterSpacing: 0,
        lineSpacing: 0.12,
        uppercase: false,
        curvedPath: nil
    )
}

public struct StickerContent: Hashable, Codable, Sendable {
    /// Identifier in the bundled sticker atlas (original assets).
    public var atlasID: String
    /// Tint (0 = none/keep original color).
    public var tintHex: UInt32?
    /// For text stickers, the string (0..N chars).
    public var string: String?
}

public enum KClipSeries: Hashable, Codable, Sendable {
    case none
    case transition(transitionID: String) // placeholder; transitions are modeled as clip boundaries
}

// MARK: - Clip

public struct Clip: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var name: String
    public var kind: KClipKind
    /// Asset handle; nil for text/sticker.
    public var assetID: UUID?

    /// Position on the timeline (canvas).
    public var start: KTime
    /// Source range within the asset (video/audio/images). For images: any range OK (stills).
    public var sourceRange: TimeRange
    /// Effectively displayed duration on canvas == speed-projected sourceRange duration.
    public var duration: KTime { SpeedMath.displayDuration(source: sourceRange.duration, speed: speed) }

    public var transform: KTransform
    public var speed: SpeedSpec
    public var audio: AudioSpec
    /// Ordered effect stack (each with parameters).
    public var effects: [EffectInstance]
    /// Optional primary filter lookup (accent color adjustments).
    public var filter: FilterInstance?
    /// Optional masks combined in order (first = bottom).
    public var masks: [MaskSpec]
    /// Animated channels (local time 0 == clip start).
    public var keyframes: KeyframeStore
    /// Entrance/exit/looping animation preset id.
    public var animation: AnimationRef?
    /// clip-level in/out trim source times are in sourceRange.
    public var text: TextContent?
    public var sticker: StickerContent?

    public init(id: UUID = UUID(),
                name: String = "Clip",
                kind: KClipKind,
                assetID: UUID? = nil,
                start: KTime,
                sourceRange: TimeRange,
                transform: KTransform = KTransform(),
                speed: SpeedSpec = SpeedSpec(),
                audio: AudioSpec = AudioSpec(),
                effects: [EffectInstance] = [],
                filter: FilterInstance? = nil,
                masks: [MaskSpec] = [],
                keyframes: KeyframeStore = .empty,
                animation: AnimationRef? = nil,
                text: TextContent? = nil,
                sticker: StickerContent? = nil) {
        self.id = id
        self.name = name
        self.kind = kind
        self.assetID = assetID
        self.start = start
        self.sourceRange = sourceRange
        self.transform = transform
        self.speed = speed
        self.audio = audio
        self.effects = effects
        self.filter = filter
        self.masks = masks
        self.keyframes = keyframes
        self.animation = animation
        self.text = text
        self.sticker = sticker
    }

    public var timelineRange: TimeRange { TimeRange(start: start, duration: duration) }
}

/// Entrance/exit/loop preset reference.
public struct AnimationRef: Hashable, Codable, Sendable {
    public enum Phase: String, Codable, Sendable { case entrance, exit, looped }
    public var phase: Phase
    public var presetID: String
    /// Duration of the animated region (entrance/exit), <= clip duration for entrance+exit split.
    public var duration: KTime
    /// Fade/scale start offset per style.
    public init(phase: Phase, presetID: String, duration: KTime) {
        self.phase = phase; self.presetID = presetID; self.duration = duration
    }
}

// MARK: - Tracks

public enum KTrackKind: String, Codable, Sendable {
    case main      // primary video/audio composition
    case overlay   // above main (image/video)
    case audio     // dedicated audio
    case text      // text layers
    case sticker   // stickers & graphics
}

/// Track ordinal tells z-order: renders bottom-to-top in array order for different-kind stacking.
public struct Track: Identifiable, Hashable, Codable, Sendable {
    public let id: UUID
    public var kind: KTrackKind
    public var name: String
    public var clips: [Clip]
    public var isHidden: Bool
    public var isLocked: Bool

    public init(id: UUID = UUID(), kind: KTrackKind, name: String = "", clips: [Clip] = [], isHidden: Bool = false, isLocked: Bool = false) {
        self.id = id
        self.kind = kind
        self.name = name.isEmpty ? kind.displayName : name
        self.clips = clips
        self.isHidden = isHidden
        self.isLocked = isLocked
    }

    public func clips(in range: TimeRange) -> [Clip] {
        clips.filter { $0.timelineRange.intersects(range) }
    }

    public func clip(at time: KTime) -> Clip? {
        clips.first { $0.timelineRange.contains(time) }
    }
}

public extension KTrackKind {
    var displayName: String {
        switch self {
        case .main: return "Main"
        case .overlay: return "Overlay"
        case .audio: return "Audio"
        case .text: return "Text"
        case .sticker: return "Sticker"
        }
    }
}

// MARK: - Canvas

public struct CanvasConfig: Hashable, Codable, Sendable {
    public var preset: KCanvasPreset
    public var widthTicks: Int         // pixel width of 1.0 normalized units (@canvas scale height)
    public var heightTicks: Int
    /// Background fill style.
    public var background: KBackground

    public init(preset: KCanvasPreset = .portrait9x16, background: KBackground = .solid(colorHex: 0x000000)) {
        self.preset = preset
        self.background = background
        let (w, h) = preset.ratio
        // Render scale: 1080px on the LONG edge baseline.
        let maxDim = 1080
        if w >= h {
            widthTicks = maxDim
            heightTicks = Int(Float(maxDim) * h / w)
        } else {
            heightTicks = maxDim
            widthTicks = Int(Float(maxDim) * w / h)
        }
    }

    public var aspect: Float { Float(widthTicks) / Float(heightTicks) }

    public var renderSize: KVec2 { KVec2(Float(widthTicks), Float(heightTicks)) }

    /// fps of the final export.
    public var fps: Rational = .fps30
}

public enum KBackground: Hashable, Codable, Sendable {
    case solid(colorHex: UInt32)
    case blurAssets
    case image(assetID: UUID)
}

// MARK: - Project

/// Canonical, non-destructive edit document.
public struct KinoProject: Hashable, Codable, Sendable {
    public struct Meta: Hashable, Codable, Sendable {
        public var id: UUID
        public var name: String
        public var createdAt: Date
        public var modifiedAt: Date
        /// Format schema version (migrations key off this).
        public var schemaVersion: Int
        public init(id: UUID = UUID(), name: String = "Untitled", createdAt: Date = Date(), modifiedAt: Date = Date(), schemaVersion: Int = KinoProject.currentSchemaVersion) {
            self.id = id
            self.name = name
            self.createdAt = createdAt
            self.modifiedAt = modifiedAt
            self.schemaVersion = schemaVersion
        }
    }

    public static let currentSchemaVersion = 1

    public var meta: Meta
    public var canvas: CanvasConfig
    public var assets: [MediaAsset]
    public var tracks: [Track]

    // Restoration state (not part of the canonical edit; persisted for UX continuity)
    public var lastPlayhead: KTime
    public var lastSelectedClipID: UUID?

    public init(meta: Meta = Meta(), canvas: CanvasConfig = CanvasConfig(), assets: [MediaAsset] = [], tracks: [Track] = [Track(kind: .main)]) {
        self.meta = meta
        self.canvas = canvas
        self.assets = assets
        self.tracks = tracks
        self.lastPlayhead = .zero
        self.lastSelectedClipID = nil
    }

    // MARK: Queries

    public var mainTrack: Track? { tracks.first { $0.kind == .main } }

    public func asset(_ id: UUID) -> MediaAsset? { assets.first { $0.id == id } }

    public func clip(_ id: UUID) -> (trackIndex: Int, clip: Clip)? {
        for (ti, track) in tracks.enumerated() {
            if let c = track.clips.first(where: { $0.id == id }) { return (ti, c) }
        }
        return nil
    }

    /// End of the composition (max end among all tracks).
    public var duration: KTime {
        tracks.reduce(KTime.zero) { acc, t in
            t.clips.reduce(acc) { max($0, $1.timelineRange.end) }
        }
    }

    /// Clips across overlays+stickers+text tracks that overlap a time, bottom-to-top render order.
    public func upperClips(at t: KTime, orderedBy kindOrder: [KTrackKind] = [.overlay, .sticker, .text]) -> [Clip] {
        kindOrder.flatMap { kind in
            tracks.filter { $0.kind == kind }.flatMap { $0.clips.filter { $0.timelineRange.contains(t) } }
        }
    }

    public func allClips() -> [Clip] { tracks.flatMap { $0.clips } }

    // MARK: Serialization

    public func encodedJSON() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> KinoProject {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        var p = try decoder.decode(KinoProject.self, from: data)
        KinoProject.migrate(&p)
        return p
    }

    /// In-place migrations from older schema versions forward.
    static func migrate(_ p: inout KinoProject) {
        if p.meta.schemaVersion < 1 {
            // v0 (unreleased dev shapes) → v1: no-op; placeholder for future migrations
            p.meta.schemaVersion = 1
        }
        if p.canvas.fps.num == 0 { p.canvas.fps = .fps30 }
    }
}
