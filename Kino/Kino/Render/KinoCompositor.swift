import AVFoundation
import CoreImage
import Foundation
import KinoEngine

// MARK: - Instruction payload

/// Immutable snapshot of everything a compositor needs for one time slice.
struct KinoSlicePayload: Sendable {
    var project: KinoProject
    var renderSizePx: CGSize
    var background: KBackground
    var transition: KinoTransition.Resolved?
    var transitionLeftID: UUID?
    var transitionRightID: UUID?
    /// Canvas time of the A|B boundary (transition window = [boundary - duration, boundary]).
    var transitionBoundary: KTime?
    var clockTrackID: CMPersistentTrackID

    func transitionProgress(at t: KTime) -> Float {
        guard let boundary = transitionBoundary, let trans = transition else { return 0 }
        let windowStart = boundary - trans.duration
        if t >= windowStart && t <= boundary {
            let ns = t.ns - windowStart.ns
            let dur = max(1, trans.duration.ns)
            return Float(ns) / Float(dur)
        }
        return t > boundary ? 1 : 0
    }
}

/// The instruction the system passes between composition and compositor.
final class KinoRenderInstruction: NSObject, AVVideoCompositionInstructionProtocol {
    let timeRange: CMTimeRange
    let enablePostProcessing = false
    let containsTweening = true
    var requiredSourceTrackIDs: [NSValue]?
    var passthroughTrackID: CMPersistentTrackID = kCMPersistentTrackID_Invalid

    let payload: KinoSlicePayload

    init(timeRange: CMTimeRange, payload: KinoSlicePayload) {
        self.timeRange = timeRange
        self.payload = payload
        super.init()
    }
}

// MARK: - Transition model

enum KinoTransition {
    enum Kind: String, CaseIterable {
        case dissolve, fade, slide, push, zoom, wipe, spin, blur, lightBeam, warp

        var display: String {
            switch self {
            case .dissolve: return "Dissolve"
            case .fade: return "Fade"
            case .slide: return "Slide"
            case .push: return "Push"
            case .zoom: return "Zoom"
            case .wipe: return "Wipe"
            case .spin: return "Spin"
            case .blur: return "Blur"
            case .lightBeam: return "Light Beam"
            case .warp: return "Warp"
            }
        }
    }

    struct Resolved {
        var kind: Kind
        var duration: KTime
        var direction: Float
    }

    /// Apply a transition between left and right layer frames at progress k in [0..1].
    static func apply(_ t: Resolved, k rawK: Float, left: LayerFrame, right: LayerFrame) -> (LayerFrame, LayerFrame) {
        var l = left
        var r = right
        let kk = min(1, max(0, rawK))
        let dir = t.direction
        switch t.kind {
        case .dissolve:
            l.transform.opacity *= 1 - kk
            r.transform.opacity *= kk
        case .fade:
            l.transform.opacity *= 1 - kk * kk
            r.transform.opacity *= kk * kk
        case .slide:
            l.transform.center.x += kk * 1.4 * dir
            r.transform.center.x += (kk - 1) * 1.4 * dir
        case .push:
            l.transform.center.x += (1 - kk) * 1.2 * dir
            r.transform.center.x += (1 - kk) * 1.2 * dir
        case .zoom:
            l.transform.scale *= 1 + kk * 0.35
            l.transform.opacity *= 1 - kk
            r.transform.scale *= 1 + (1 - kk) * 1.3
            r.transform.opacity *= min(1, kk * 2)
        case .wipe:
            l.transform.opacity *= 1 - kk
            r.transform.opacity *= kk
            r.transform.crop = KCropRect(x: 0, y: 0, width: max(0.001, kk), height: 1)
        case .spin:
            l.transform.rotation += kk * -90
            r.transform.rotation += (1 - kk) * 90
            l.transform.opacity *= 1 - kk * kk
            r.transform.opacity *= kk
        case .blur:
            l.transform.opacity *= 1 - kk
            r.transform.opacity *= kk
        case .lightBeam:
            l.transform.opacity *= 1 - kk
            r.transform.opacity *= kk
        case .warp:
            l.transform.scale *= 1 + kk * 0.2
            r.transform.scale *= 1 - kk * 0.2
            l.transform.opacity *= 1 - kk
            r.transform.opacity *= kk
        }
        return (l, r)
    }
}

// MARK: - Compositor

final class KinoCompositor: NSObject, AVVideoCompositing {
    static let shared = KinoCompositor()

    private let renderQueue = DispatchQueue(label: "kino.compositor", qos: .userInitiated)
    private let renderer = CanvasRenderer.shared
    private var context: AVVideoCompositionRenderContext?

    var sourcePixelBufferAttributes: [String: Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA],
        kCVPixelBufferIOSurfacePropertiesKey as String: [String: Any](),
    ]

    var requiredPixelBufferAttributesForRenderContext: [String: Any] = [
        kCVPixelBufferPixelFormatTypeKey as String: [kCVPixelFormatType_32BGRA,
                                                     kCVPixelFormatType_64RGBAHalf,
                                                                                                          kCVPixelFormatType_422YpCbCr10,
                                                     kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange],
    ]

    func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        context = newRenderContext
    }

    func startRequest(_ request: AVAsynchronousVideoCompositionRequest) {
        // per-request rendering is handled on the dedicated queue; finish on main is safe.
        renderQueue.async {
            guard let instruction = request.videoCompositionInstruction as? KinoRenderInstruction else {
                // no instruction → deliver nothing
                return
                return
            }

            let t = KTime(request.compositionTime)
            let project = instruction.payload.project
            let renderSize = instruction.payload.renderSizePx
            self.renderer.setTextRenderSize(renderSize)

            var layers = RenderTree.layers(at: t, project: project)

            // transition adjustment
            if let trans = instruction.payload.transition {
                let k = instruction.payload.transitionProgress(at: t)
                if let leftID = instruction.payload.transitionLeftID,
                   let rightID = instruction.payload.transitionRightID,
                   let li = layers.firstIndex(where: { $0.clipID == leftID }),
                   let ri = layers.firstIndex(where: { $0.clipID == rightID }) {
                    let pair = KinoTransition.apply(trans, k: k, left: layers[li], right: layers[ri])
                    layers[li] = pair.0
                    layers[ri] = pair.1
                }
            }

            var canvas: CIImage = self.renderer.renderBackground(project, renderSize: renderSize, base: nil)

            for layer in layers {
                let assetSize = layer.assetSize ?? KVec2(0, 0)
                let rendered = self.renderer.render(layer: layer, assetSize: assetSize, renderSize: renderSize, time: t.seconds)
                    .cropped(to: CGRect(origin: .zero, size: renderSize))
                canvas = self.blendOver(canvas, layer: rendered, blend: layer.transform.blend)
            }

            let dst: CVPixelBuffer
            if let buffered = self.context?.newPixelBuffer() {
                dst = buffered
            } else if let buffered = request.renderContext.newPixelBuffer() {
                dst = buffered
            } else {
                return
            }
            // resolve optional: render context may be nil before first render
            let bounds = CGRect(origin: .zero, size: renderSize)
            self.renderer.ctx.render(canvas.cropped(to: bounds), to: dst, bounds: bounds, colorSpace: CGColorSpaceCreateDeviceRGB())
            request.finish(withComposedVideoFrame: dst)
        }
    }

    func cancelAllPendingVideoCompositionRequests() {
        // AVPlayer replaces items; requests finish/fail via render context lifetime
    }

    private func blendOver(_ base: CIImage, layer: CIImage, blend: KBlendMode) -> CIImage {
        switch blend {
        case .normal:
            return layer.composited(over: base)
        case .multiply: return layer.applyingFilter("CIMultiplyBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .screen: return layer.applyingFilter("CIScreenBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .additive: return layer.applyingFilter("CIAddBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .overlay: return layer.applyingFilter("CIOverlayBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .darken: return layer.applyingFilter("CIDarkenBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .lighten: return layer.applyingFilter("CILightenBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .colorDodge: return layer.applyingFilter("CIColorDodgeBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .colorBurn: return layer.applyingFilter("CIColorBurnBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .softLight: return layer.applyingFilter("CISoftLightBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .hardLight: return layer.applyingFilter("CIHardLightBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .difference: return layer.applyingFilter("CIDifferenceBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .exclusion: return layer.applyingFilter("CIExclusionBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .hue: return layer.applyingFilter("CIHueBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .saturation: return layer.applyingFilter("CISaturationBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .color: return layer.applyingFilter("CIColorBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        case .luminosity: return layer.applyingFilter("CILuminosityBlendMode", parameters: [kCIInputBackgroundImageKey: base])
        }
    }
}
