import CoreImage
import KinoEngine
import UIKit

/// Original Kino sticker atlas: emoji glyphs + tinted system-shape symbols
/// rendered with our own treatment (stroke, glow, tint). No third-party assets.
enum StickerAtlas {
    public static let catalog: [(id: String, emoji: String)] = [
        ("heart", "❤️"), ("fire", "🔥"), ("star", "⭐"), ("party", "🎉"),
        ("rocket", "🚀"), ("crown", "👑"), ("sparkles", "✨"), ("flower", "🌸"),
        ("cat", "🐱"), ("dog", "🐶"), ("handwave", "👋"), ("thumbsup", "👍"),
        ("laugh", "😂"), ("wow", "🤩"), ("cry", "😭"), ("heart-eyes", "😍"),
        ("sun", "🌞"), ("rainbow", "🌈"), ("check", "✅"), ("boom", "💥"),
        ("brain", "🧠"), ("laptop", "💻"), ("music", "🎵"), ("trophy", "🏆"),
    ]

    private static var cache: [String: CIImage] = [:]

    static func symbolImage(_ id: String) -> UIImage? {
        let system: [String: String] = [
            "arrow-left": "arrow.left", "arrow-right": "arrow.right", "arrow-up": "arrow.up",
            "arrow-down": "arrow.down", "circle-solid": "circle.fill", "square-solid": "square.fill",
            "triangle-solid": "triangle.fill", "plus-solid": "plus.circle.fill",
            "bolt": "bolt.fill", "heartline": "heart.fill", "pointer": "hand.point.up.left.fill",
            "smile-solid": "smile.fill", "flag-solid": "flag.fill", "bell-solid": "bell.fill",
        ]
        guard let sname = system[id] else { return nil }
        let cfg = UIImage.SymbolConfiguration(pointSize: 96, weight: .medium)
        return UIImage(systemName: sname, withConfiguration: cfg)
    }

    static func image(sticker: StickerContent) -> CIImage {
        let key = "\(sticker.atlasID)|\(sticker.tintHex ?? 0)|\(sticker.string ?? "")"
        if let hit = cache[key] { return hit }
        var out: CIImage?
        if let emoji = catalog.first(where: { $0.id == sticker.atlasID })?.emoji {
            out = render(emoji: emoji, tint: sticker.tintHex)
        } else if let ui = symbolImage(sticker.atlasID) {
            out = render(image: ui, tint: sticker.tintHex)
        }
        guard let result = out else { return CIImage.empty() }
        if cache.count > 60 { cache.removeAll() }
        cache[key] = result
        return result
    }

    private static func render(emoji: String, tint: UInt32?) -> CIImage? {
        let size = CGSize(width: 256, height: 256)
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let img = UIGraphicsImageRenderer(size: size, format: fmt).image { ctx in
            let font = UIFont.systemFont(ofSize: 190)
            let str = NSAttributedString(string: emoji, attributes: [.font: font])
            let s = str.boundingRect(with: size, options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size
            str.draw(at: CGPoint(x: (size.width - s.width) / 2, y: (size.height - s.height) / 2))
        }
        let base: CIImage
        if let ci = img.ciImage {
            base = ci
        } else if let cg = img.cgImage {
            base = CIImage(cgImage: cg)
        } else {
            return nil
        }
        if let tint {
            let r = CGFloat((tint >> 16) & 0xFF) / 255
            let g = CGFloat((tint >> 8) & 0xFF) / 255
            let b = CGFloat(tint & 0xFF) / 255
            let c0 = CIImage(red: r, green: g, blue: b, alpha: 1)
            let c1 = CIImage(red: 0, green: 0, blue: 0, alpha: 0)
            return base.applyingFilter("CIFalseColor", parameters: [
                "inputColor0": c0,
                "inputColor1": c1,
            ])
        }
        return base
    }

    private static func render(image: UIImage, tint: UInt32?) -> CIImage? {
        let base: CIImage
        if let ci = image.ciImage {
            base = ci
        } else if let cg = image.cgImage {
            base = CIImage(cgImage: cg)
        } else {
            return nil
        }
        guard let tint else { return base }
        let gray = base.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputGVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputBVector": CIVector(x: 0.2126, y: 0.7152, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let r = CGFloat((tint >> 16) & 0xFF) / 255
        let g = CGFloat((tint >> 8) & 0xFF) / 255
        let b = CGFloat(tint & 0xFF) / 255
        let tintColor = CIImage(color: CIColor(red: r, green: g, blue: b, alpha: 1))
        return gray.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputImageKey: tintColor])
    }
}
