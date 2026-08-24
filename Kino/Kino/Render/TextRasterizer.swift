import CoreImage
import KinoEngine
import UIKit

/// Rasterizes TextContent into a canvas-sized CIImage, cached by content fingerprint.
/// Used by the compositor so preview == export text rendering.
enum TextRasterizer {
    static var currentRenderSize = CGSize(width: 1080, height: 1920)
    private static var cache: [String: CIImage] = [:]

    static func raster(text: TextContent, renderSize: CGSize) -> CIImage {
        let key = "\(text.string)|\(text.fontName)|\(text.fontSize)|\(text.colorHex)|\(text.opacity)|\(text.alignment)|\(text.strokeColorHex ?? 0)|\(text.strokeWidth)|\(text.backgroundPadding)|\(text.letterSpacing)|\(text.lineSpacing)|\(text.uppercase)|\(Int(renderSize.width))x\(Int(renderSize.height))"
        if let hit = cache[key] { return hit }

        let W = renderSize.width
        let H = renderSize.height
        let fmt = UIGraphicsImageRendererFormat()
        fmt.scale = 1
        fmt.opaque = false
        let size = CGSize(width: W, height: H)
        let renderer = UIGraphicsImageRenderer(size: size, format: fmt)
        let image = renderer.image { ctx in
            let cgc = ctx.cgContext
            let fontScale = CGFloat(text.fontSize) * H
            let baseFont = UIFont(name: text.fontName, size: fontScale) ?? UIFont.systemFont(ofSize: fontScale, weight: text.fontWeight > 0.7 ? .bold : .semibold)
            let color = color(fromHex: text.colorHex, alpha: CGFloat(text.opacity))
            let para = NSMutableParagraphStyle()
            para.alignment = alignment(text.alignment)
            para.lineSpacing = fontScale * CGFloat(text.lineSpacing)
            var attrs: [NSAttributedString.Key: Any] = [
                .font: baseFont,
                .foregroundColor: color,
                .paragraphStyle: para,
                .kern: fontScale * CGFloat(text.letterSpacing),
            ]
            // stroke
            if text.strokeWidth > 0, let stroke = text.strokeColorHex {
                let sw = fontScale * CGFloat(text.strokeWidth) * 2
                let strokeColor = uicolor(fromHex: stroke)
                attrs[.strokeColor] = strokeColor
                attrs[.strokeWidth] = -sw
            }
            // shadow
            if text.shadow {
                let sh = NSShadow()
                sh.shadowColor = uicolor(fromHex: text.shadowColorHex ?? 0xAA000000).withAlphaComponent(0.6)
                sh.shadowBlurRadius = fontScale * 0.08
                sh.shadowOffset = CGSize(width: 0, height: -fontScale * 0.05)
                attrs[.shadow] = sh
            }
            let str = NSAttributedString(string: text.uppercase ? text.string.uppercased() : text.string,
                                         attributes: attrs)
            let strSize = str.boundingRect(with: CGSize(width: W * 0.94, height: H * 0.9),
                                           options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).size

            // background
            if let bg = text.backgroundColorHex {
                let pad = fontScale * CGFloat(text.backgroundPadding)
                let bgRect = CGRect(x: (W - strSize.width) / 2 - pad, y: (H - strSize.height) / 2 - pad,
                                    width: strSize.width + pad * 2, height: strSize.height + pad * 2)
                let path = UIBezierPath(roundedRect: bgRect, cornerRadius: pad * 0.8)
                uicolor(fromHex: bg).withAlphaComponent(0.82).setFill()
                path.fill()
            }
            str.draw(in: CGRect(x: (W - strSize.width) / 2,
                                y: (H - strSize.height) / 2,
                                width: strSize.width,
                                height: strSize.height))
        }

        let ci = CIImage(image: image, options: [.colorSpace: CGColorSpaceCreateDeviceRGB()]) ?? CIImage.empty()
        if cache.count > 40 { cache.removeAll() }
        cache[key] = ci
        return ci
    }

    private static func alignment(_ a: Int) -> NSTextAlignment {
        switch a {
        case 0: return .left
        case 2: return .right
        default: return .center
        }
    }

    static func color(fromHex hex: UInt32, alpha: CGFloat = 1) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: alpha)
    }

    static func uicolor(fromHex hex: UInt32) -> UIColor {
        UIColor(red: CGFloat((hex >> 16) & 0xFF) / 255,
                green: CGFloat((hex >> 8) & 0xFF) / 255,
                blue: CGFloat(hex & 0xFF) / 255,
                alpha: CGFloat((hex >> 24) & 0xFF) / 255)
    }
}
