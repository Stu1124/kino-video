import AVFoundation
import CoreImage
import CoreImage.CIFilterBuiltins
import KinoEngine
import UIKit

/// Per-frame layer pipeline: source frame → crop → transform → color → effects →
/// masks → chroma key → canvas-space layer. Runs inside the custom compositor,
/// so the preview and the export render through the identical code path.
final class CanvasRenderer {

    static let shared = CanvasRenderer()

    private let ctx = CIContext(options: [.cacheIntermediates: true])

    /// Render a single layer into canvas space.
    /// `inRect` is the canvas pixel extent (origin 0,0, size W*scale, H*scale).
    func render(layer: LayerFrame, assetSize: KVec2, renderSize: CGSize, time: Double) -> CIImage {
        var image = sourceImage(layer: layer)

        if image.extent.width < 1 || image.extent.height < 1 {
            // silent dead layer (missing asset) — transparent placeholder
            return CIImage.empty()
        }

        // 1. crop in source space
        let crop = layer.transform.crop.clamped()
        let srcW = image.extent.width
        let srcH = image.extent.height
        let cropRect = CGRect(x: crop.x * srcW, y: crop.y * srcH,
                              width: max(1, crop.width * srcW), height: max(1, crop.height * srcH))
        image = image.cropped(to: cropRect)

        // 2. fit-transform
        image = transform(image: image, layer: layer, assetSize: KVec2(Float(cropRect.width), Float(cropRect.height)), renderSize: renderSize)

        guard var cimage = optionalClipped(image, renderSize: renderSize) else { return CIImage.empty() }

        // 3. chroma key first (before color, matches broadcast workflows)
        if let chroma = layer.chromaKey {
            cimage = applyChromaKey(cimage, chroma: chroma)
        }

        // 4. full-stack color adjustments
        cimage = applyAdjustments(cimage, adj: layer.adjustments)

        // 5. effects stack (ordered)
        for effect in layer.effects {
            cimage = applyEffect(cimage, effect: effect, time: time)
        }

        // 6. opacity
        let opacity = max(0, min(1, layer.transform.opacity))
        if opacity < 0.9999 {
            cimage = cimage.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: opacity),
            ])
        }

        // 7. masks (in canvas space)
        for mask in layer.masks {
            cimage = applyMask(cimage, mask: mask, renderSize: renderSize)
        }

        return cimage
    }

    // MARK: source decode

    private func sourceImage(layer: LayerFrame) -> CIImage {
        switch layer.kind {
        case .video:
            if let assetID = layer.assetID, let uri = currentAssetURI(assetID) {
                return decodeFrame(uri: uri, at: layer.sourceTime)
            }
            return CIImage.empty()
        case .image:
            if let assetID = layer.assetID, let uri = currentAssetURI(assetID), let ci = cachedImage(uri: uri) {
                return ci
            }
            return CIImage.empty()
        case .text:
            if let text = layer.text {
                return TextRasterizer.raster(text: text, transform: layer.transform,
                                             renderSize: textRenderSize())
            }
            return CIImage.empty()
        case .sticker:
            if let s = layer.sticker {
                return StickerAtlas.image(sticker: s)
            }
            return CIImage.empty()
        default:
            return CIImage.empty()
        }
    }

    // MARK: context bridge (overridden per session)

    /// The active editor's asset uri registry (injected by the session).
    static var uriResolver: ((UUID) -> String?)?

    func currentAssetURI(_ id: UUID) -> String? {
        if let r = CanvasRenderer.uriResolver { return r(id) }
        return nil
    }

    private var renderSizeForText = CGSize(width: 1080, height: 1920)
    func textRenderSize() -> CGSize {
        renderSizeForText
    }
    func setTextRenderSize(_ s: CGSize) {
        renderSizeForText = s
        TextRasterizer.currentRenderSize = s
    }

    // MARK: decode

    private var decoderCache = VideoTarget()

    final class VideoTarget {
        var gen: AVAssetImageGenerator?
        var lastURI: String?
    }

    private func decodeFrame(uri: String, at time: KTime) -> CIImage {
        let url = URL(string: uri)
        guard let url else { return CIImage.empty() }
        if decoderCache.lastURI != uri || decoderCache.gen == nil {
            let asset = AVURLAsset(url: url)
            let gen = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            decoderCache.gen = gen
            decoderCache.lastURI = uri
        }
        guard let cg = try? decoderCache.gen?.copyCGImage(at: time.cmTime, actualTime: nil) else {
            return CIImage.empty()
        }
        return CIImage(cgImage: cg)
    }

    private var imageCache: [String: CIImage] = [:]

    private func cachedImage(uri: String) -> CIImage? {
        if let hit = imageCache[uri] { return hit }
        guard let url = URL(string: uri),
              let ui = UIImage(contentsOfFile: url.path),
              let ci = ui.ciImage ?? ui.cgImage.map(CIImage.init(cgImage:)) else { return nil }
        imageCache[uri] = ci
        return ci
    }

    // MARK: transform

    private func transform(image: CIImage, layer: LayerFrame, assetSize: KVec2, renderSize: CGSize) -> CIImage {
        let W = renderSize.width
        let H = renderSize.height
        let tf = layer.transform

        var affine: CGAffineTransform = .identity
        // base fill scale
        let base = Double(KFitMath.fillScale(asset: assetSize, canvas: KVec2(Float(W), Float(H))))
        let scale = base * Double(tf.scale)

        // center source (after crop) from origin to canvas center, scaled
        affine = affine.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let cw = CGFloat(assetSize.x) * 1
        // translate so source bottom-left lands at canvas center-ish
        let offX = (W - cw * CGFloat(scale)) / 2
        let offY = (H - CGFloat(assetSize.y) * CGFloat(scale)) / 2
        affine = affine.concatenating(CGAffineTransform(translationX: offX, y: offY))

        // flip handling about canvas center
        if tf.flipX || tf.flipY {
            var f: CGAffineTransform = CGAffineTransform(translationX: W / 2, y: H / 2)
            f = f.concatenating(CGAffineTransform(scaleX: tf.flipX ? -1 : 1, y: tf.flipY ? -1 : 1))
            f = f.concatenating(CGAffineTransform(translationX: -W / 2, y: -H / 2))
            affine = affine.concatenating(f)
        }

        // rotation about canvas center, then opacify user center offset
        if tf.rotation != 0 {
            var r = CGAffineTransform(translationX: W / 2, y: H / 2)
            r = r.concatenating(CGAffineTransform(rotationAngle: CGFloat(tf.rotation) * .pi / 180))
            r = r.concatenating(CGAffineTransform(translationX: -W / 2, y: -H / 2))
            affine = affine.concatenating(r)
        }

        // user center: (0,0=top-left, 1,1=bottom-right in UI) → CI bottom-left coords
        let shift = CGPoint(x: CGFloat(tf.center.x - 0.5) * W, y: CGFloat(0.5 - tf.center.y) * H)
        affine = affine.concatenating(CGAffineTransform(translationX: shift.x, y: shift.y))

        return image.transformed(by: affine)
    }

    private func optionalClipped(_ image: CIImage, renderSize: CGSize) -> CIImage? {
        let full = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        return image.cropped(to: full)
    }

    // MARK: color adjustments

    func applyAdjustments(_ image: CIImage, adj: ColorAdjust) -> CIImage {
        var image = image
        let neutral = ColorAdjust.neutral == adj
        if neutral { return image }

        if adj.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": Float(adj.exposure)])
        }
        if adj.brightness != 0 {
            image = image.applyingFilter("CIColorControls", parameters: ["inputBrightness": CGFloat(adj.brightness * 0.55)])
        }
        if adj.contrast != 0 {
            image = image.applyingFilter("CIColorControls", parameters: ["inputContrast": CGFloat(1.0 + adj.contrast * 0.45)])
        }
        if adj.saturation != 0 {
            image = image.applyingFilter("CIColorControls", parameters: ["inputSaturation": CGFloat(1.0 + adj.saturation * 1.6)])
        }
        if adj.highlights != 0 || adj.shadows != 0 {
            let h = CGFloat(0.2 + adj.highlights * 0.35)
            let s = CGFloat(0.2 + adj.shadows * 0.5)
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": h,
                "inputShadowAmount": s,
            ])
        }
        if adj.vibrance != 0 {
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": CGFloat(adj.vibrance * 1.4)])
        }
        if adj.temperature != 0 || adj.tint != 0 {
            let tint = CIVector(x: 6500 + CGFloat(adj.temperature) * 3000, y: 0 + CGFloat(adj.tint) * 400)
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": tint,
                "inputTargetNeutral": CIVector(x: 6500, y: 0),
            ])
        }
        if adj.fade != 0 {
            let fade = CGFloat(adj.fade * 0.45)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: fade * 0.10, y: fade * 0.10, z: fade * 0.10, w: 0),
            ])
        }
        if adj.sharpen != 0 {
            image = image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": CGFloat(adj.sharpen * 1.2)])
        }
        if adj.vignette != 0 {
            image = image.applyingFilter("CIVignette", parameters: [
                "inputIntensity": CGFloat(adj.vignette * 1.35),
                "inputRadius": 1.4,
            ])
        }
        if adj.grain != 0 {
            image = applyGrain(image, amount: adj.grain)
        }
        if adj.hueShift != 0 {
            image = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": CGFloat(adj.hueShift) * .pi])
        }
        return image
    }

    private func applyGrain(_ image: CIImage, amount: Float) -> CIImage {
        let noise = CIFilter.randomGenerator().outputImage!
            .cropped(to: CGRect(x: 0, y: 0, width: image.extent.width, height: image.extent.height))
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.2126, z: 0.2126, w: 0),
            "inputGVector": CIVector(x: 0.7152, y: 0.7152, z: 0.7152, w: 0),
            "inputBVector": CIVector(x: 0.0722, y: 0.0722, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let grain = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
        ]).applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.5)),
        ])
        return image.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputImageKey: grain])
    }

    // MARK: effects

    private func applyEffect(_ image: CIImage, effect: ResolvedEffect, time: Double) -> CIImage {
        let p = effect.params
        let amt = Float(effect.strength)
        switch effect.specID {
        case "kino.blur.gaussian":
            return image.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": (p["radius"] ?? 0.5) * CGFloat(amt) * 28])
        case "kino.blur.radial":
            return image.applyingFilter("CIZoomBlur", parameters: [
                "inputAmount": (p["radius"] ?? 0.5) * CGFloat(amt) * 0.9,
            ])
        case "kino.blur.motion":
            return image.applyingFilter("CIMotionBlur", parameters: [
                "inputAngle": CGFloat(p["angle"] ?? 0) * .pi / 180,
                "inputRadius": (p["radius"] ?? 0.5) * CGFloat(amt) * 24,
            ])
        case "kino.blur.focus":
            let r = (p["radius"] ?? 0.5) * CGFloat(amt) * 40
            let angle = CGFloat(p["angle"] ?? 0)
            let focus = image.applyingFilter("CIFocusBlur", parameters: [
                "inputRadius": r,
                "inputAngle": angle,
                "inputSharpness": CGFloat(amt * 0.4),
            ])
            return focus
        case "kino.light.flare":
            let center = CIVector(x: CGFloat(p["x"] ?? 0.5) * image.extent.width, y: (1 - CGFloat(p["y"] ?? 0.5)) * image.extent.height)
            return CIKernels.shared.k("flare")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -100, dy: -100) }, arguments: [image, center, CGFloat(amt), CGFloat(time)])
        case "kino.light.leak":
            let hue = CGFloat(p["hue"] ?? 0.7) * 2 * .pi
            let hot = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": hue])
                .applyingFilter("CIColorInvert", parameters: [:])
            let blended = image.applyingFilter("CIScreenBlendMode", parameters: [
                kCIInputImageKey: hot.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amt * 0.35))]),
            ])
            return blended
        case "kino.light.glow":
            return image.applyingFilter("CIBloom", parameters: [
                "inputRadius": (p["threshold"] ?? 0.6) * CGFloat(amt) * 30,
                "inputIntensity": CGFloat(amt * 0.65),
            ])
        case "kino.distort.bulge":
            let cx = CGFloat(p["x"] ?? 0.5) * image.extent.width
            let cy = (1 - CGFloat(p["y"] ?? 0.5)) * image.extent.height
            let radius = (p["radius"] ?? 0.5) * CGFloat(min(image.extent.width, image.extent.height)) * 0.5
            return image.applyingFilter("CIBumpDistortion", parameters: [
                "inputCenter": CIVector(x: cx, y: cy),
                "inputRadius": max(10, radius),
                "inputScale": CGFloat(amt) * 0.7 * (p["radius"] ?? 0.5) * 5,
            ])
        case "kino.distort.twist":
            let radius = (p["radius"] ?? 0.5) * CGFloat(min(image.extent.width, image.extent.height)) * 0.6
            return image.applyingFilter("CITwirlDistortion", parameters: [
                "inputCenter": CIVector(x: image.extent.midX, y: image.extent.midY),
                "inputRadius": max(10, radius),
                "inputAngle": CGFloat(amt) * 2 * .pi * (p["radius"] ?? 0.5) * 2.2,
            ])
        case "kino.distort.zoom":
            return image.applyingFilter("CIZoomBlur", parameters: [
                "inputAmount": CGFloat(amt) * 0.5,
            ])
        case "kino.distort.wave":
            let band = image.applyingFilter("CIBandsDistortion", parameters: [
                "inputFrequency": (p["frequency"] ?? 1) * 4 * CGFloat(amt),
                "inputStrength": 0.6,
            ])
            return band
        case "kino.distort.smear":
            let angle = CGFloat(p["angle"] ?? 45) * .pi / 180
            return CIKernels.shared.k("smear")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -80, dy: -80) }, arguments: [image, Float(angle), CGFloat(amt), CGFloat(time)])
        case "kino.color.pixelate":
            let extent = max(image.extent.width, image.extent.height)
            return image.applyingFilter("CIPixellate", parameters: [
                "inputScale": max(2, extent * CGFloat(0.05 + (p["size"] ?? 0.5) * 0.16) * CGFloat(amt)),
            ])
        case "kino.color.chromatic":
            return CIKernels.shared.k("rgbSplit")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -60, dy: -60) }, arguments: [image, Float(amt), CIVector(x: 0, y: 1), CGFloat(time)])
        case "kino.color.invert":
            return image.applyingFilter("CIColorInvert", parameters: [:])
        case "kino.color.mono":
            return image.applyingFilter("CIPhotoEffectMono", parameters: [:])
        case "kino.color.mix":
            let h = CGFloat((p["hue"] ?? 0.65) * 2 * .pi)
            let tinted = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": h])
            return image.applyingFilter("CISoftLightBlendMode", parameters: [
                kCIInputImageKey: tinted.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amt * 0.45))]),
            ])
        case "kino.grain.film":
            return applyGrain(image, amount: (p["size"] ?? 0.35) * amt)
        case "kino.grain.noise":
            return applyGrain(image, amount: (p["size"] ?? 0.5) * amt)
        case "kino.vignette.soft":
            return image.applyingFilter("CIVignette", parameters: [
                "inputIntensity": CGFloat(amt) * (p["radius"] ?? 0.5) * 1.8,
                "inputRadius": 1.7,
            ])
        case "kino.edge.sharpen":
            return image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.8 * CGFloat(amt)])
        case "kino.edge.highlights":
            return CIKernels.shared.k("xray")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -10, dy: -10) }, arguments: [image, Float(amt), 0.0])
        case "kino.edge.xray":
            return CIKernels.shared.k("xray")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -10, dy: -10) }, arguments: [image, Float(amt * 1.5), CGFloat(time)])
        case "kino.glitch.shift":
            return CIKernels.shared.k("rgbSplit")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -60, dy: -60) }, arguments: [image, Float(amt * (p["shift"] ?? 0.5)), CIVector(x: 1, y: 0), CGFloat(time)])
        case "kino.glitch.slices":
            return CIKernels.shared.k("slices")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -30, dy: -30) }, arguments: [image, CGFloat(p["count"] ?? 8), CGFloat(time), CGFloat(amt)])
        case "kino.glitch.static":
            return CIKernels.shared.k("static")
                .apply(extent: image.extent, roiCallback: { $1 }, arguments: [image, CGFloat(amt), CGFloat(time)])
        case "kino.retro.vhs":
            return CIKernels.shared.k("vhs")
                .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -30, dy: -30) }, arguments: [image, CGFloat(p["tracking"] ?? 0.4), CGFloat(time)])
        case "kino.retro.crt":
            let scan = image.applyingFilter("CIColorMatrix", parameters: [
                "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0),
            ])
            return scan.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.6 * CGFloat(amt)])
            .applyingFilter("CIPixellate", parameters: ["inputScale": 3])
        default:
            return image
        }
    }

    // MARK: chroma key

    func applyChromaKey(_ image: CIImage, chroma: ChromaKeySpec) -> CIImage {
        CIKernels.shared.k("chroma")
            .apply(extent: image.extent, roiCallback: { $1.insetBy(dx: -20, dy: -20) }, arguments: [
                image,
                CGFloat(chroma.keyColor.r), CGFloat(chroma.keyColor.g), CGFloat(chroma.keyColor.b),
                CGFloat(chroma.similarity), CGFloat(chroma.smoothness), CGFloat(chroma.spill), CGFloat(chroma.edgeFeather),
            ])
    }

    // MARK: masks

    /// Rasterize a mask into a full-canvas alpha image via Core Graphics, then
    /// multiply-composite it over the layer. Feather = gaussian blur on the mask.
    func applyMask(_ image: CIImage, mask: MaskSpec, renderSize: CGSize) -> CIImage {
        guard let maskIMG = Self.rasterizeMask(mask, renderSize: renderSize) else { return image }
        var m = maskIMG
        if mask.feather > 0.001 {
            let blurPx = mask.feather * Float(min(renderSize.width, renderSize.height)) * 0.5
            m = m.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blurPx])
        }
        if mask.inverted {
            m = m.applyingFilter("CIColorInvert", parameters: [:])
        }
        return image.applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: m])
    }

    /// White image where masked, transparent elsewhere (alpha = mask value).
    static func rasterizeMask(_ mask: MaskSpec, renderSize: CGSize) -> CIImage? {
        let W = Int(renderSize.width)
        let H = Int(renderSize.height)
        guard W > 0, H > 0 else { return nil }
        // UI coords: y-down normalized (0,0 top-left)
        let cx = mask.center.x * Float(W)
        let cy = mask.center.y * Float(H)
        let sx = mask.size.x * Float(W)
        let sy = mask.size.y * Float(H)
        let angle = CGFloat(mask.rotation) * .pi / 180

        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
        // CGContext has y-up; we draw in UI space by flipping: translate(0,H) scale(1,-1)
        ctx.translateBy(x: 0, y: CGFloat(H))
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: CGFloat(cx), y: CGFloat(cy))
        ctx.rotate(by: angle)

        let rect = CGRect(x: -CGFloat(sx) / 2, y: -CGFloat(sy) / 2, width: CGFloat(sx), height: CGFloat(sy))

        switch mask.kind {
        case .rectangle:
            ctx.fill(rect)
        case .circle:
            ctx.fillEllipse(in: rect)
        case .linear:
            let half = CGFloat(sx) / 2
            let linePath = CGMutablePath()
            linePath.move(to: CGPoint(x: -half, y: 0))
            linePath.addLine(to: CGPoint(x: half, y: 0))
            linePath.addLine(to: CGPoint(x: half, y: CGFloat(H)))
            linePath.addLine(to: CGPoint(x: -half, y: CGFloat(H)))
            linePath.closeSubpath()
            ctx.fillPath()
        case .split:
            let side = mask.splitSide < 0.5 ? CGFloat(-1) : CGFloat(1)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(W) * side, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(W) * side, y: CGFloat(H)))
            path.addLine(to: CGPoint(x: 0, y: CGFloat(H)))
            path.closeSubpath()
            ctx.fillPath()
        case .freeform, .custom:
            guard mask.points.count >= 3 else { return nil }
            let path = CGMutablePath()
            let pts = mask.points.map {
                CGPoint(x: ($0.x - mask.center.x) * Float(W), y: ($0.y - mask.center.y) * Float(H))
            }
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()
            ctx.fillPath()
        }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }
}

// MARK: - Background rendering

extension CanvasRenderer {
    /// Render the canvas background (solid color, blur of first video, or image).
    func renderBackground(_ project: KinoProject, renderSize: CGSize, base: CIImage?) -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        switch project.canvas.background {
        case .solid(let hex):
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
        case .blurAssets:
            guard let base else {
                return CIImage(color: .black).cropped(to: rect)
            }
            let fit = KFitMath.fillScale(asset: KVec2(Float(base.extent.width), Float(base.extent.height)),
                                         canvas: KVec2(Float(renderSize.width), Float(renderSize.height)))
            let scaled = base.transformed(by: CGAffineTransform(scaleX: CGFloat(fit), y: CGFloat(fit)))
            let blurred = scaled.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": 90])
            return blurred.cropped(to: rect)
        case .image(let assetID):
            if let uri = CanvasRenderer.uriResolver?(assetID), let img = UIImage(contentsOfFile: URL(string: uri)?.path ?? "") {
                let fit = KFitMath.fillScale(asset: KVec2(Float(img.size.width), Float(img.size.height)),
                                             canvas: KVec2(Float(renderSize.width), Float(renderSize.height)))
                return CIImage(cgImage: img.cgImage!).transformed(by: CGAffineTransform(scaleX: CGFloat(fit), y: CGFloat(fit)))
                    .cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        }
    }
}
