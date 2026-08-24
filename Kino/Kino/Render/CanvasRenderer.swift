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

    let ctx = CIContext(options: [.cacheIntermediates: true])

    /// Resolves asset UIImage/BGRA by uri (injected by the editor session).
    static var uriResolver: ((UUID) -> String?)?
    static var imageProvider: ((String) -> CIImage?)?

    private var decoderGen: AVAssetImageGenerator?
    private var decoderURI: String?
    private var imageCache: [String: CIImage] = [:]

    private var textRenderSize = CGSize(width: 1080, height: 1920)

    func setTextRenderSize(_ s: CGSize) {
        textRenderSize = s
        TextRasterizer.currentRenderSize = s
    }

    func currentAssetURI(_ id: UUID) -> String? {
        if let r = CanvasRenderer.uriResolver { return r(id) }
        return nil
    }

    // MARK: render one layer

    func render(layer: LayerFrame, assetSize: KVec2, renderSize: CGSize, time: Double) -> CIImage {
        var image = sourceImage(layer: layer)
        if image.extent.width < 1 || image.extent.height < 1 {
            return CIImage.empty()
        }

        // 1. crop in source space
        let crop = layer.transform.crop.clamped()
        let srcW = image.extent.width
        let srcH = image.extent.height
        let cropRect = CGRect(x: CGFloat(crop.x) * srcW, y: CGFloat(crop.y) * srcH,
                              width: max(1, CGFloat(crop.width) * srcW), height: max(1, CGFloat(crop.height) * srcH))
        image = image.cropped(to: cropRect)
        let croppedW = Float(srcW * CGFloat(crop.width))
        let croppedH = Float(srcH * CGFloat(crop.height))
        let croppedSize = KVec2(croppedW, croppedH)

        // 2. fit-transform
        image = transform(image: image, assetSize: croppedSize, layer: layer, renderSize: renderSize)
        var cimage = image.cropped(to: CGRect(origin: .zero, size: renderSize))
        if cimage.extent.width < 1 { return CIImage.empty() }

        // 3. chroma key
        if let chroma = layer.chromaKey {
            cimage = applyChromaKey(cimage, chroma: chroma)
        }

        // 4. color adjustments
        cimage = applyAdjustments(cimage, adj: layer.adjustments)

        // 5. effects stack
        for effect in layer.effects {
            cimage = applyEffect(cimage, effect: effect, time: time)
        }

        // 6. opacity
        let opacity = max(0, min(1, layer.transform.opacity))
        if opacity < 0.9999 {
            cimage = cimage.applyingFilter("CIColorMatrix", parameters: [
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(opacity)),
            ])
        }

        // 7. masks
        for mask in layer.masks {
            cimage = applyMask(cimage, mask: mask, renderSize: renderSize)
        }
        return cimage
    }

    // MARK: source images

    private func sourceImage(layer: LayerFrame) -> CIImage {
        switch layer.kind {
        case .video:
            guard let assetID = layer.assetID, let uri = currentAssetURI(assetID) else { return CIImage.empty() }
            return decodeFrame(uri: uri, at: layer.sourceTime)
        case .image:
            guard let assetID = layer.assetID,
                  let uri = currentAssetURI(assetID),
                  let ci = CanvasRenderer.imageProvider?(uri) ?? cachedImage(uri: uri)
            else { return CIImage.empty() }
            return ci
        case .text:
            guard let text = layer.text else { return CIImage.empty() }
            return TextRasterizer.raster(text: text, renderSize: textRenderSize)
        case .sticker:
            guard let s = layer.sticker else { return CIImage.empty() }
            return StickerAtlas.image(sticker: s)
        default:
            return CIImage.empty()
        }
    }

    private func decodeFrame(uri: String, at time: KTime) -> CIImage {
        guard let url = URL(string: uri) else { return CIImage.empty() }
        if decoderURI != uri || decoderGen == nil {
            let gen = AVAssetImageGenerator(asset: AVURLAsset(url: url))
            gen.appliesPreferredTrackTransform = true
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            decoderGen = gen
            decoderURI = uri
        }
        guard let cg = try? decoderGen?.copyCGImage(at: time.cmTime, actualTime: nil) else {
            return CIImage.empty()
        }
        return CIImage(cgImage: cg)
    }

    private func cachedImage(uri: String) -> CIImage? {
        if let hit = imageCache[uri] { return hit }
        guard let url = URL(string: uri),
              let ui = UIImage(contentsOfFile: url.path),
              let ci = ui.cgImage.map(CIImage.init(cgImage:)) else { return nil }
        if imageCache.count > 64 { imageCache.removeAll() }
        imageCache[uri] = ci
        return ci
    }

    // MARK: transform

    private func transform(image: CIImage, assetSize: KVec2, layer: LayerFrame, renderSize: CGSize) -> CIImage {
        let W = renderSize.width
        let H = renderSize.height
        let tf = layer.transform

        let baseFloat = KFitMath.fillScale(asset: assetSize, canvas: KVec2(Float(W), Float(H)))
        let scale = CGFloat(baseFloat) * CGFloat(tf.scale)

        var affine: CGAffineTransform = .identity
        affine = affine.concatenating(CGAffineTransform(scaleX: scale, y: scale))
        let offX = (W - CGFloat(assetSize.x) * scale) / 2
        let offY = (H - CGFloat(assetSize.y) * scale) / 2
        affine = affine.concatenating(CGAffineTransform(translationX: offX, y: offY))

        if tf.flipX || tf.flipY {
            var f = CGAffineTransform(translationX: W / 2, y: H / 2)
            f = f.concatenating(CGAffineTransform(scaleX: tf.flipX ? -1 : 1, y: tf.flipY ? -1 : 1))
            f = f.concatenating(CGAffineTransform(translationX: -W / 2, y: -H / 2))
            affine = affine.concatenating(f)
        }

        if tf.rotation != 0 {
            var r = CGAffineTransform(translationX: W / 2, y: H / 2)
            r = r.concatenating(CGAffineTransform(rotationAngle: CGFloat(tf.rotation) * .pi / 180))
            r = r.concatenating(CGAffineTransform(translationX: -W / 2, y: -H / 2))
            affine = affine.concatenating(r)
        }

        let shiftX = CGFloat(tf.center.x - 0.5) * W
        let shiftY = CGFloat(0.5 - tf.center.y) * H
        affine = affine.concatenating(CGAffineTransform(translationX: shiftX, y: shiftY))

        return image.transformed(by: affine)
    }

    // MARK: color adjustments

    func applyAdjustments(_ image: CIImage, adj: ColorAdjust) -> CIImage {
        guard !adj.isNeutral else { return image }
        var image = image
        if adj.exposure != 0 {
            image = image.applyingFilter("CIExposureAdjust", parameters: ["inputEV": adj.exposure])
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
            image = image.applyingFilter("CIHighlightShadowAdjust", parameters: [
                "inputHighlightAmount": 0.2 + CGFloat(adj.highlights * 0.35),
                "inputShadowAmount": 0.2 + CGFloat(adj.shadows * 0.5),
            ])
        }
        if adj.vibrance != 0 {
            image = image.applyingFilter("CIVibrance", parameters: ["inputAmount": CGFloat(adj.vibrance * 1.4)])
        }
        if adj.temperature != 0 || adj.tint != 0 {
            image = image.applyingFilter("CITemperatureAndTint", parameters: [
                "inputNeutral": CIVector(x: 6500 + CGFloat(adj.temperature) * 3000, y: CGFloat(adj.tint) * 400),
                "inputTargetNeutral": CIVector(x: 6500, y: 0),
            ])
        }
        if adj.fade != 0 {
            let fade = CGFloat(adj.fade * 0.12)
            image = image.applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": CIVector(x: 1, y: 0, z: 0, w: 0),
                "inputGVector": CIVector(x: 0, y: 1, z: 0, w: 0),
                "inputBVector": CIVector(x: 0, y: 0, z: 1, w: 0),
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: fade, y: fade, z: fade, w: 0),
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
        let rect = CGRect(x: 0, y: 0, width: image.extent.width, height: image.extent.height)
        guard let noise = CIFilter.randomGenerator().outputImage?.cropped(to: rect) else { return image }
        let mono = noise.applyingFilter("CIColorMatrix", parameters: [
            "inputRVector": CIVector(x: 0.2126, y: 0.2126, z: 0.2126, w: 0),
            "inputGVector": CIVector(x: 0.7152, y: 0.7152, z: 0.7152, w: 0),
            "inputBVector": CIVector(x: 0.0722, y: 0.0722, z: 0.0722, w: 0),
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
        ])
        let centered = mono.applyingFilter("CIColorMatrix", parameters: [
            "inputBiasVector": CIVector(x: -0.5, y: -0.5, z: -0.5, w: 0),
        ])
        let faded = centered.applyingFilter("CIColorMatrix", parameters: [
            "inputAVector": CIVector(x: 0, y: 0, z: 0, w: CGFloat(amount * 0.5)),
        ])
        return faded.composited(over: image).applyingFilter("CIOverlayBlendMode", parameters: [kCIInputImageKey: image])
            .applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
    }

    // MARK: effects

    private func applyEffect(_ image: CIImage, effect: ResolvedEffect, time: Double) -> CIImage {
        let amt = CGFloat(effect.strength)
        let extent = image.extent
        guard let spec = EffectInstance.spec(effect.specID) else { return image }
        func p(_ key: String) -> Float { effect.params[key] ?? spec.param(key)?.defaultValue ?? 0 }
        if amt <= 0 { return image }

        switch spec.family {
        case "Blur":
            let radius = CGFloat(p("radius")) * amt * 28
            let blur = image.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": max(0.1, radius)])
            return blur
        case "Light":
            if effect.specID == "kino.light.flare" {
                let center = CIVector(x: (image.extent.width) * CGFloat(p("x")), y: (1 - CGFloat(p("y"))) * image.extent.height)
                return CIKernels.shared.k("flare").apply(extent: extent, roiCallback: { $1.insetBy(dx: -120, dy: -120) },
                                                         arguments: [image, center, amt, CGFloat(time)]) ?? image
            }
            if effect.specID == "kino.light.glow" {
                return image.applyingFilter("CIBloom", parameters: ["inputRadius": CGFloat(p("threshold")) * amt * 30, "inputIntensity": amt * 0.65])
            }
            let hot = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": CGFloat(p("hue") * 4)])
            let tinted = hot.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amt * 0.4)])
            return tinted.composited(over: image).applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        case "Color":
            if effect.specID == "kino.color.pixelate" {
                let scalePx = CGFloat(p("size")) * amt * 60 + 2
                return image.applyingFilter("CIPixellate", parameters: ["inputScale": scalePx])
            }
            if effect.specID == "kino.color.chromatic" {
                return CIKernels.shared.k("rgbSplit").apply(extent: extent, roiCallback: { $1.insetBy(dx: -80, dy: -80) },
                                                            arguments: [image, Float(amt), CIVector(x: 0, y: 1), CGFloat(time)]) ?? image
            }
            if effect.specID == "kino.color.invert" {
                return image.applyingFilter("CIColorInvert", parameters: [:])
            }
            if effect.specID == "kino.color.mono" {
                return image.applyingFilter("CIPhotoEffectMono", parameters: [:])
            }
            let h = CGFloat(p("hue") * 2 * .pi)
            let tinted = image.applyingFilter("CIHueAdjust", parameters: ["inputAngle": h])
            let faded = tinted.applyingFilter("CIColorMatrix", parameters: ["inputAVector": CIVector(x: 0, y: 0, z: 0, w: amt * 0.45)])
            return faded.composited(over: image).applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: image])
        case "Distort":
            let radius = CGFloat(p("radius")) * max(extent.width, extent.height) * 0.4
            if effect.specID == "kino.distort.bulge" {
                let cx = extent.width * CGFloat(p("x"))
                let cy = extent.height * (1 - CGFloat(p("y")))
                return image.applyingFilter("CIBumpDistortion", parameters: [
                    "inputCenter": CIVector(x: cx, y: cy),
                    "inputRadius": max(10, radius),
                    "inputScale": 0.3 * amt,
                ])
            }
            if effect.specID == "kino.distort.twist" {
                return image.applyingFilter("CITwirlDistortion", parameters: [
                    "inputCenter": CIVector(x: extent.midX, y: extent.midY),
                    "inputRadius": max(10, radius),
                    "inputAngle": amt * 2.2 * .pi * CGFloat(p("radius")),
                ])
            }
            if effect.specID == "kino.distort.zoom" {
                return image.applyingFilter("CIZoomBlur", parameters: ["inputAmount": amt * 0.4])
            }
            if effect.specID == "kino.distort.smear" {
                let angle = Float(CGFloat(p("angle")) * .pi / 180)
                return CIKernels.shared.k("smear").apply(extent: extent, roiCallback: { $1.insetBy(dx: -100, dy: -100) },
                                                         arguments: [image, angle, amt, CGFloat(time)]) ?? image
            }
            return image
        case "Grain":
            return applyGrain(image, amount: p("size") * effect.strength)
        case "Vignette":
            return image.applyingFilter("CIVignette", parameters: [
                "inputIntensity": amt * CGFloat(p("radius")) * 1.8,
                "inputRadius": 1.7,
            ])
        case "Edge":
            if effect.specID == "kino.edge.xray" {
                return CIKernels.shared.k("xray").apply(extent: extent, roiCallback: { $1.insetBy(dx: -20, dy: -20) },
                                                        arguments: [image, Float(amt * 1.5), CGFloat(time)]) ?? image
            }
            return image.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.8 * amt])
        case "Glitch":
            if effect.specID == "kino.glitch.shift" {
                return CIKernels.shared.k("rgbSplit").apply(extent: extent, roiCallback: { $1.insetBy(dx: -100, dy: -100) },
                                                            arguments: [image, Float(amt) * p("shift"), CIVector(x: 1, y: 0), CGFloat(time)]) ?? image
            }
            if effect.specID == "kino.glitch.slices" {
                return CIKernels.shared.k("slices").apply(extent: extent, roiCallback: { $1.insetBy(dx: -60, dy: -60) },
                                                          arguments: [image, CGFloat(p("count")), CGFloat(time), amt]) ?? image
            }
            return CIKernels.shared.k("static").apply(extent: extent, roiCallback: { $1 },
                                                      arguments: [image, amt, CGFloat(time)]) ?? image
        case "Retro":
            if effect.specID == "kino.retro.vhs" {
                return CIKernels.shared.k("vhs").apply(extent: extent, roiCallback: { $1.insetBy(dx: -60, dy: -60) },
                                                       arguments: [image, CGFloat(p("tracking")), CGFloat(time)]) ?? image
            }
            let pix = image.applyingFilter("CIPixellate", parameters: ["inputScale": 3])
            return pix.applyingFilter("CISharpenLuminance", parameters: ["inputSharpness": 0.5 * amt])
        default:
            return image
        }
    }

    // MARK: chroma key

    func applyChromaKey(_ image: CIImage, chroma: ChromaKeySpec) -> CIImage {
        let ext = image.extent
        let args: [Any] = [
            image,
            CGFloat(chroma.keyColor.r), CGFloat(chroma.keyColor.g), CGFloat(chroma.keyColor.b),
            CGFloat(chroma.similarity), CGFloat(chroma.smoothness), CGFloat(chroma.spill), CGFloat(chroma.edgeFeather),
        ]
        return CIKernels.shared.k("chroma").apply(extent: ext, roiCallback: { $1.insetBy(dx: -30, dy: -30) }, arguments: args) ?? image
    }

    // MARK: masks

    func applyMask(_ image: CIImage, mask: MaskSpec, renderSize: CGSize) -> CIImage {
        guard let maskIMG = Self.rasterizeMask(mask, renderSize: renderSize) else { return image }
        var m = maskIMG
        if mask.feather > 0.001 {
            let blurPx = CGFloat(mask.feather) * min(renderSize.width, renderSize.height) * CGFloat(0.5)
            m = m.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": blurPx])
        }
        if mask.inverted {
            m = m.applyingFilter("CIColorInvert", parameters: [:])
        }
        return m.composited(over: image).applyingFilter("CIMultiplyCompositing", parameters: [kCIInputBackgroundImageKey: image])
    }

    /// White where masked (alpha = mask value), transparent elsewhere.
    static func rasterizeMask(_ mask: MaskSpec, renderSize: CGSize) -> CIImage? {
        let W = Int(renderSize.width)
        let H = Int(renderSize.height)
        guard W > 0, H > 0 else { return nil }
        let cx = mask.center.x * Float(W)
        let cy = mask.center.y * Float(H)
        let sx = max(mask.size.x * Float(W), 1)
        let sy = max(mask.size.y * Float(H), 1)
        let angle = CGFloat(mask.rotation) * .pi / 180

        guard let ctx = CGContext(data: nil, width: W, height: H, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.clear(CGRect(x: 0, y: 0, width: W, height: H))
        ctx.setFillColor(CGColor(gray: 1, alpha: 1))
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
            let path = CGMutablePath()
            path.move(to: CGPoint(x: -half, y: 0))
            path.addLine(to: CGPoint(x: half, y: 0))
            path.addLine(to: CGPoint(x: half, y: CGFloat(H) * 2))
            path.addLine(to: CGPoint(x: -half, y: CGFloat(H) * 2))
            path.closeSubpath()
            ctx.fillPath()
        case .split:
            let side = mask.splitSide < 0.5 ? CGFloat(-1) : CGFloat(1)
            let path = CGMutablePath()
            path.move(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(W) * 2 * side, y: 0))
            path.addLine(to: CGPoint(x: CGFloat(W) * 2 * side, y: CGFloat(H) * 2))
            path.addLine(to: CGPoint(x: 0, y: CGFloat(H) * 2))
            path.closeSubpath()
            ctx.fillPath()
        case .freeform, .custom:
            guard mask.points.count >= 3 else { return nil }
            let pts = mask.points.map { CGPoint(x: CGFloat($0.x - mask.center.x) * CGFloat(W), y: CGFloat($0.y - mask.center.y) * CGFloat(H)) }
            let path = CGMutablePath()
            path.move(to: pts[0])
            for pt in pts.dropFirst() { path.addLine(to: pt) }
            path.closeSubpath()
            ctx.fillPath()
        }
        guard let cg = ctx.makeImage() else { return nil }
        return CIImage(cgImage: cg)
    }
}

// MARK: - Background

extension CanvasRenderer {
    func renderBackground(_ project: KinoProject, renderSize: CGSize, base: CIImage?) -> CIImage {
        let rect = CGRect(x: 0, y: 0, width: renderSize.width, height: renderSize.height)
        switch project.canvas.background {
        case .solid(let hex):
            let r = CGFloat((hex >> 16) & 0xFF) / 255
            let g = CGFloat((hex >> 8) & 0xFF) / 255
            let b = CGFloat(hex & 0xFF) / 255
            return CIImage(color: CIColor(red: r, green: g, blue: b)).cropped(to: rect)
        case .blurAssets:
            guard let base else { return CIImage(color: .black).cropped(to: rect) }
            let fit = KFitMath.fillScale(asset: KVec2(Float(base.extent.width), Float(base.extent.height)),
                                         canvas: KVec2(Float(rect.width), Float(rect.height)))
            let scaled = base.transformed(by: CGAffineTransform(scaleX: CGFloat(fit), y: CGFloat(fit)))
            let blurred = scaled.transformed(by: CGAffineTransform(translationX: (rect.width - scaled.extent.width) / 2,
                                                                   y: (rect.height - scaled.extent.height) / 2))
            return blurred.applyingFilter("CIGaussianBlur", parameters: ["inputRadius": min(rect.width, rect.height) * 0.25]).cropped(to: rect)
        case .image(let assetID):
            if let uri = CanvasRenderer.uriResolver?(assetID),
               let img = CanvasRenderer.imageProvider?(uri) {
                let fit = KFitMath.fillScale(asset: KVec2(Float(img.extent.width), Float(img.extent.height)),
                                             canvas: KVec2(Float(rect.width), Float(rect.height)))
                return img.transformed(by: CGAffineTransform(scaleX: CGFloat(fit), y: CGFloat(fit)))
                    .cropped(to: rect)
            }
            return CIImage(color: .black).cropped(to: rect)
        }
    }
}
