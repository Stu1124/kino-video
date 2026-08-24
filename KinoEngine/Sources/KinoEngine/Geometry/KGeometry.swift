import Foundation

// MARK: - 2D primitives (platform-free; CoreGraphics has no Linux presence)

public struct KVec2: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float

    public init(_ x: Float, _ y: Float) { self.x = x; self.y = y }
    public init(doubleX x: Double, _ y: Double) { self.x = Float(x); self.y = Float(y) }
    public static let zero = KVec2(0, 0)
    public static let one = KVec2(1, 1)

    public static func + (_ a: KVec2, _ b: KVec2) -> KVec2 { KVec2(a.x + b.x, a.y + b.y) }
    public static func - (_ a: KVec2, _ b: KVec2) -> KVec2 { KVec2(a.x - b.x, a.y - b.y) }
    public static func * (_ a: KVec2, _ s: Float) -> KVec2 { KVec2(a.x * s, a.y * s) }
    public static func * (_ s: Float, _ a: KVec2) -> KVec2 { a * s }
    public static func / (_ a: KVec2, _ s: Float) -> KVec2 { KVec2(a.x / s, a.y / s) }

    public var lengthSquared: Float { x * x + y * y }
    public var length: Float { sqrt(x * x + y * y) }

    public func dot(_ b: KVec2) -> Float { x * b.x + y * b.y }
    public func rotated(_ radians: Float) -> KVec2 {
        let c = cos(radians), s = sin(radians)
        return KVec2(x * c - y * s, x * s + y * c)
    }
    public func normalized(_ epsilon: Float = 1e-8) -> KVec2 {
        let l = length
        guard l > epsilon else { return .zero }
        return self / l
    }
    public func lerp(_ b: KVec2, _ t: Float) -> KVec2 { self + (b - self) * t }
}

/// Little helper so the same code compiles on Swift (CGFloat alias).
public struct CGFloat_Ish {
    public let v: Float
    public init(_ v: Float) { self.v = v }
}

public struct KRect: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }

    public var midX: Float { x + width / 2 }
    public var midY: Float { y + height / 2 }
    public var center: KVec2 { KVec2(midX, midY) }
    public var min: KVec2 { KVec2(x, y) }
    public var max: KVec2 { KVec2(x + width, y + height) }

    public func contains(_ p: KVec2) -> Bool {
        p.x >= x && p.x <= x + width && p.y >= y && p.y <= y + height
    }
}

// MARK: - Aspect / canvas math

public enum KCanvasPreset: String, Codable, CaseIterable, Sendable {
    case portrait9x16, landscape16x9, square, portrait4x5, portrait3x4, landscape4x3, landscape3x2, portrait2x3, wide21x9

    public var ratio: (w: Float, h: Float) {
        switch self {
        case .portrait9x16: return (9, 16)
        case .landscape16x9: return (16, 9)
        case .square: return (1, 1)
        case .portrait4x5: return (4, 5)
        case .portrait3x4: return (3, 4)
        case .landscape4x3: return (4, 3)
        case .landscape3x2: return (3, 2)
        case .portrait2x3: return (2, 3)
        case .wide21x9: return (21, 9)
        }
    }

    public var display: String {
        switch self {
        case .portrait9x16: return "9:16"
        case .landscape16x9: return "16:9"
        case .square: return "1:1"
        case .portrait4x5: return "4:5"
        case .portrait3x4: return "3:4"
        case .landscape4x3: return "4:3"
        case .landscape3x2: return "3:2"
        case .portrait2x3: return "2:3"
        case .wide21x9: return "21:9"
        }
    }
}

/// Fit / fill math. This single implementation is used by the preview,
/// the final renderer and thumbnails so every surface agrees exactly.
public enum KFitMath {
    /// Factor to scale an asset of `assetSize` so it *fits* the `canvas`.
    public static func fitScale(asset: KVec2, canvas: KVec2) -> Float {
        guard asset.x > 0, asset.y > 0, canvas.x > 0, canvas.y > 0 else { return 1 }
        return min(canvas.x / asset.x, canvas.y / asset.y)
    }
    /// Factor to scale an asset so it *fills* the canvas.
    public static func fillScale(asset: KVec2, canvas: KVec2) -> Float {
        guard asset.x > 0, asset.y > 0, canvas.x > 0, canvas.y > 0 else { return 1 }
        return max(canvas.x / asset.x, canvas.y / asset.y)
    }
    /// Offset added to the zero-position (asset center = canvas center) when scaled.
    public static func offset(asset: KVec2, canvas: KVec2, scale s: Float) -> KVec2 {
        KVec2((canvas.x - asset.x * s) * 0.5, (canvas.y - asset.y * s) * 0.5)
    }
    /// Normalized crop rect (0..1 in asset space) that fills a canvas for aspect conversion.
    /// E.g., 16:9 asset into 9:16 canvas crops the width.
    public static func fillCrop(asset: KVec2, canvas: KVec2) -> KCropRect {
        let aspectAsset = asset.x / asset.y
        let aspectCanvas = canvas.x / canvas.y
        if aspectAsset > aspectCanvas {
            let cropW = aspectCanvas / aspectAsset
            return KCropRect(x: (1 - cropW) * 0.5, y: 0, width: cropW, height: 1)
        } else {
            let cropH = aspectAsset / aspectCanvas
            return KCropRect(x: 0, y: (1 - cropH) * 0.5, width: 1, height: cropH)
        }
    }
}

/// Normalized crop rectangle in [0,1] asset space.
public struct KCropRect: Hashable, Codable, Sendable {
    public var x: Float
    public var y: Float
    public var width: Float
    public var height: Float

    public init(x: Float, y: Float, width: Float, height: Float) {
        self.x = x; self.y = y; self.width = width; self.height = height
    }
    public static let full = KCropRect(x: 0, y: 0, width: 1, height: 1)

    public func clamped() -> KCropRect {
        KCropRect(x: max(0, x), y: max(0, y),
                  width: min(1, max(0.0001, width)),
                  height: min(1, max(0.0001, height)))
    }
}

// MARK: - Transform

/// 2D transform for a clip as displayed on the canvas.
/// Anchor point is the clip's center in canvas space (before crop).
public struct KTransform: Hashable, Codable, Sendable {
    /// Center position in canvas normalized coordinates: [0,1] where (0.5,0.5) = canvas center.
    public var center: KVec2
    /// Uniform scale (1 = asset fits canvas per fit settings).
    public var scale: Float
    /// Rotation in degrees, clockwise positive.
    public var rotation: Float
    /// 0 = invisible, 1 = fully opaque.
    public var opacity: Float
    public var flipX: Bool
    public var flipY: Bool
    /// Normalized crop in asset space.
    public var crop: KCropRect
    /// Blend mode enum.
    public var blend: KBlendMode

    public init(center: KVec2 = KVec2(0.5, 0.5),
                scale: Float = 1,
                rotation: Float = 0,
                opacity: Float = 1,
                flipX: Bool = false,
                flipY: Bool = false,
                crop: KCropRect = .full,
                blend: KBlendMode = .normal) {
        self.center = center
        self.scale = scale
        self.rotation = rotation
        self.opacity = opacity
        self.flipX = flipX
        self.flipY = flipY
        self.crop = crop
        self.blend = blend
    }

    /// Map a canvas-space point to this transform's normalized output for hit-testing.
    public static let identity = KTransform()
}

public enum KBlendMode: String, Codable, CaseIterable, Sendable {
    case normal
    case multiply
    case screen
    case additive
    case overlay
    case darken
    case lighten
    case colorDodge
    case colorBurn
    case softLight
    case hardLight
    case difference
    case exclusion
    case hue
    case saturation
    case color
    case luminosity

    public var display: String {
        switch self {
        case .normal: return "Normal"
        case .multiply: return "Multiply"
        case .screen: return "Screen"
        case .additive: return "Add"
        case .overlay: return "Overlay"
        case .darken: return "Darken"
        case .lighten: return "Lighten"
        case .colorDodge: return "Dodge"
        case .colorBurn: return "Burn"
        case .softLight: return "Soft Light"
        case .hardLight: return "Hard Light"
        case .difference: return "Difference"
        case .exclusion: return "Exclusion"
        case .hue: return "Hue"
        case .saturation: return "Saturation"
        case .color: return "Color"
        case .luminosity: return "Luminosity"
        }
    }
}
