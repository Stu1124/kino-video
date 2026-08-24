import CoreImage
import Foundation

/// Compiled custom Core Image kernels used by the Kino effects engine.
/// All kernels operate in normalized [0..1] canvas coordinates so results are
/// identical at preview scale (small) and export scale (1080p/4K).
final class CIKernels {
    static let shared = CIKernels()

    private let chromaKey: CIKernel
    private let rgbSplit: CIKernel
    private let slices: CIKernel
    private let staticNoise: CIKernel
    private let vhs: CIKernel
    private let edgeXray: CIKernel
    private let lensFlare: CIKernel
    private let smear: CIKernel
    private let punchMono: CIKernel

    private init() {
        func kernel(_ source: String) -> CIKernel {
            CIKernel(source: source) ?? CIKernel(source: """
            kernel vec4 fallback(sampler src) { return sample(src, samplerCoord(src)); }
            """)!
        }
        let fallback = CIKernel(source: """
        kernel vec4 fallback(sampler src) { return sample(src, samplerCoord(src)); }
        """)!
        chromaKey = CIKernel(source: Self.kChromaKey) ?? fallback
        rgbSplit = CIKernel(source: Self.kRgbSplit) ?? fallback
        slices = CIKernel(source: Self.kSlices) ?? fallback
        staticNoise = CIKernel(source: Self.kStatic) ?? fallback
        vhs = CIKernel(source: Self.kVHS) ?? fallback
        edgeXray = CIKernel(source: Self.kXRay) ?? fallback
        lensFlare = CIKernel(source: Self.kFlare) ?? fallback
        smear = CIKernel(source: Self.kSmear) ?? fallback
        punchMono = CIKernel(source: Self.kPunchMono) ?? fallback
    }

    // MARK: lookups

    func k(_ id: String) -> CIKernel {
        switch id {
        case "chroma": return chromaKey
        case "rgbSplit": return rgbSplit
        case "slices": return slices
        case "static": return staticNoise
        case "vhs": return vhs
        case "xray": return edgeXray
        case "flare": return lensFlare
        case "smear": return smear
        case "punchMono": return punchMono
        default: return chromaKey
        }
    }

    // MARK: kernel sources (normalized coords; destCoord/extent)

    static let kChromaKey = """
    kernel vec4 chroma(sampler src, float keyR, float keyG, float keyB,
                       float similarity, float smoothness, float spillAmt, float feather) {
        vec2 n = destCoord() / vec2(1.0, 1.0);
        vec2 d = vec2(destCoord().x, destCoord().y);
        vec2 ext = samplerExtent(src).zw;
        vec2 coords = samplerCoord(src);
        if (coords.x < 0.0 || coords.y < 0.0 || coords.x > ext.x || coords.y > ext.y) {
            return vec4(0.0, 0.0, 0.0, 0.0);
        }
        vec4 p = sample(src, coords);
        vec3 key = vec3(keyR, keyG, keyB);
        float dist = distance(p.rgb, key);
        float maxDist = sqrt(3.0);
        float normDist = dist / maxDist;
        float alpha = smoothstep(similarity, similarity + smoothness, normDist);
        // spill suppression: remove key hue from semi-transparent fringes
        float keySat = max(key.r, max(key.g, key.b)) - min(key.r, min(key.g, key.b));
        float spill = clamp(spillAmt * (1.0 - alpha) * keySat * 4.0, 0.0, 0.9);
        vec3 rgb = p.rgb;
        float luminance = dot(rgb, vec3(0.2126, 0.7152, 0.0722));
        rgb = mix(rgb, vec3(luminance), spill * 0.35);
        // feather adds a soft transparent rim
        alpha = clamp(alpha + feather * 0.1 * (1.0 - alpha), 0.0, 1.0);
        return vec4(rgb * alpha, alpha);
    }
    """

    static let kRgbSplit = """
    kernel vec4 rgbSplit(sampler src, float amount, vec2 offset, float time) {
        vec2 ext = samplerExtent(src).zw;
        vec2 p = samplerCoord(src);
        vec2 o = offset * ext * (0.5 + 0.5 * sin(time * 2.0 + p.x * 30.0)) * amount;
        float r = sample(src, p + o).r;
        float g = sample(src, p).g;
        float b = sample(src, p - o).b;
        vec4 c = sample(src, p);
        return vec4(r, g, b, c.a);
    }
    """

    static let kSlices = """
    kernel vec4 slices(sampler src, float count, float time, float strength) {
        vec2 ext = samplerExtent(src).zw;
        vec2 p = samplerCoord(src);
        float band = floor(p.y * count);
        float jitter = sin(band * 12.9898 + floor(time * 6.0) * 7.0) * 0.5 + 0.5;
        float shift = (jitter - 0.5) * (0.06 * strength);
        float xoff = shift * ext.x;
        float2 q = p;
        q.x = p.x + xoff;
        q.x = mod(q.x, ext.x);
        return sample(src, q);
    }
    """

    static let kStatic = """
    kernel vec4 static(sampler src, float amount, float time) {
        float n = fract(sin(dot(floor(destCoord() * 3.0) + floor(time * 12.0), vec2(12.9898, 78.233))) * 43758.5453);
        vec4 c = sample(src, samplerCoord(src));
        float mixv = clamp(amount * 0.6 * n, 0.0, 1.0);
        return vec4(mix(c.rgb, vec3(0.5 + n * 0.5), mixv), c.a);
    }
    """

    static let kVHS = """
    kernel vec4 vhs(sampler src, float tracking, float time) {
        vec2 ext = samplerExtent(src).zw;
        vec2 p = samplerCoord(src);
        float band = sin(p.y * 600.0 + time * 3.0) * 0.5 + 0.5;
        float jitter = sin(p.y * 21.0 + time * 1.7) * tracking * 0.004 * ext.x;
        p.x = mod(p.x + jitter, ext.x);
        vec4 c = sample(src, p);
        // scanline darkening
        float scan = 0.92 + 0.08 * band;
        // chroma noise
        float n = fract(sin(dot(floor(destCoord()) + floor(time * 24.0), vec2(12.9898, 78.233))) * 43758.5453);
        vec3 shift = vec3(c.r + n * 0.05 * tracking, c.g, c.b + n * 0.03 * tracking);
        return vec4(shift * scan, c.a);
    }
    """

    static let kXRay = """
    kernel vec4 xray(sampler src, float strength, float time) {
        vec4 c = sample(src, samplerCoord(src));
        float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
        float edgeLum = dot(sample(src, samplerCoord(src) + vec2(2.5, 0.0)).rgb, vec3(0.2126, 0.7152, 0.0722));
        float d = (lum - edgeLum) * strength * 6.0;
        vec3 rgba = clamp(vec3(lum + d * 1.4, lum * 0.6, 1.0 - lum * 0.4), 0.0, 1.0);
        return vec4(rgba, c.a);
    }
    """

    static let kFlare = """
    kernel vec4 flare(sampler src, vec2 center, float strength, float time) {
        vec2 ext = samplerExtent(src).zw;
        vec2 p = samplerCoord(src) / ext;
        vec2 c = center;
        vec2 d = p - c;
        float r = length(d);
        // anamorphic streak
        float streak = exp(-abs(d.y) * 9.0) * 0.55;
        // rings
        float ring = sin(r * 60.0 - time * 4.0) * 0.12 * exp(-r * 3.0);
        // halo
        float halo = exp(-r * 8.0) * 0.8;
        vec3 tint = vec3(0.55, 0.68, 1.0) * 0.55 + vec3(1.0, 0.62, 0.4) * 0.45;
        vec3 add = tint * (halo * 0.8 + streak + ring) * strength;
        vec4 c4 = sample(src, samplerCoord(src));
        vec3 outColor = c4.rgb + add;
        outColor = clamp(outColor, 0.0, 1.0);
        return vec4(outColor, c4.a);
    }
    """

    static let kSmear = """
    kernel vec4 smear(sampler src, float angleRad, float amount, float time) {
        vec2 dir = vec2(cos(angleRad), sin(angleRad));
        float2 stepV = dir * (1.0 + amount * 9.0);
        vec2 p = samplerCoord(src);
        vec4 cOwn = sample(src, p);
        vec4 cB = sample(src, p + stepV);
        vec4 cD = sample(src, p - stepV);
        vec4 outC = cOwn * 0.72 + (cB + cD) * 0.14 * (1.0 + 0.2 * sin(time * 8.0));
        outC.rgb = mix(cOwn.rgb, outC.rgb, amount + 0.25);
        // keep edges clean
        outC.a = cOwn.a;
        return outC;
    }
    """

    static let kPunchMono = """
    kernel vec4 punchMono(sampler src, float amount) {
        vec4 c = sample(src, samplerCoord(src));
        float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
        vec3 outC = mix(c.rgb, vec3(lum), amount);
        return vec4(outC * 1.06, c.a);
    }
    """
}
