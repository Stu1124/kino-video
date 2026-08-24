import AVFoundation
import Foundation
import KinoEngine
import UIKit

/// Disk+memory cache for thumbnails and waveforms so timeline/preview never block.
public final class MediaCache {
    public static let shared = MediaCache()

    private let session = URLSession(configuration: .default)
    private let mem = NSCache<NSString, NSData>()
    private let disk: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let dir = caches.appendingPathComponent("MediaCache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        disk = dir
        mem.countLimit = 400
    }

    private func key(base: String, ext: String) -> String {
        let digest = base.data(using: .utf8)!.base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return "\(digest).\(ext)"
    }

    func data(for base: String, ext: String) -> Data? {
        let k = key(base: base, ext: ext)
        if let d = mem.object(forKey: k as NSString) { return d as Data }
        let url = disk.appendingPathComponent(k)
        guard let d = try? Data(contentsOf: url) else { return nil }
        mem.setObject(d as NSData, forKey: k as NSString)
        return d
    }

    func store(_ data: Data, base: String, ext: String) {
        let k = key(base: base, ext: ext)
        mem.setObject(data as NSData, forKey: k as NSString)
        try? data.write(to: disk.appendingPathComponent(k), options: .atomic)
    }
}

/// Generates thumbnails for media URIs asynchronously with cancellation +
/// cache integration + a compact backing store for timeline filmstrips.
public final class ThumbnailService {
    public static let shared = ThumbnailService()

    private let cache = MediaCache.shared
    private let queue = DispatchQueue(label: "kino.thumbgen", qos: .userInitiated)
    private var jobs: [String: Bool] = [:]   // in-flight guard

    /// Loads a thumbnail image synchronously-fast when cached; otherwise kicks off
    /// async generation. Pass a CGImage-backed layer array via completion.
    public func thumbnail(targetSize: CGSize, uri: String, at time: KTime, completion: @escaping (CGImage?) -> Void) {
        let base = "\(uri)#\(Int64(time.ns))"
        if let d = cache.data(for: base, ext: "thb"),
           let img = UIImage(data: d)?.cgImage {
            completion(img)
            return
        }
        Task.detached(priority: .userInitiated) { [weak self] () -> Void in
            guard let self else { return }
            let url2 = URL(string: uri) ?? URL(string: "file:///tmp/x")!
            guard url2.path.isEmpty == false else { return }
            let asset = AVURLAsset(url: url2)
            let gen: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = targetSize
            gen.requestedTimeToleranceBefore = CMTime(seconds: 0, preferredTimescale: 600)
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.06, preferredTimescale: 600)
            do {
                let img = try gen.copyCGImage(at: time.cmTime, actualTime: nil)
                let png = UIImage(cgImage: img).jpegData(compressionQuality: 0.62)!
                self.cache.store(png, base: base, ext: "thb")
                DispatchQueue.main.async { completion(img) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// Filmstrip frames for a clip (used by timeline cells). Cached per (uri,startSrc,len).
    public func filmstrip(uri: String, sourceRange: TimeRange, duration: KTime, frames: Int, maxSize: CGSize,
                          completion: @escaping ([CGImage]) -> Void) {
        let start = Int64(sourceRange.start.ns)
        let end = Int64(sourceRange.end.ns)
        let base = "strip-\(uri)#\(start)-\(end)-\(frames)"
        // cached strip bitmap?
        let cachedRaw: Data? = cache.data(for: base, ext: "strip")
        if let d = cachedRaw {
            let bitmaps: [CGImage]? = decodeStrip(d)
            if let packed = bitmaps {
                completion(packed)
                return
            }
        }
        queue.async { [weak self] in
            guard let self else { return }
            let url2 = URL(string: uri)
            guard let url2 else { return }
            let asset = AVURLAsset(url: url2)
            let gen: AVAssetImageGenerator = AVAssetImageGenerator(asset: asset)
            gen.appliesPreferredTrackTransform = true
            gen.maximumSize = maxSize
            gen.requestedTimeToleranceBefore = .zero
            gen.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)
            var images: [CGImage] = []
            for i in 0..<frames {
                let frac = Float(i + 0.5) / Float(frames)
                let t = sourceRange.start + sourceRange.duration.scaled(by: frac)
                if let image = try? gen.copyCGImage(at: t.cmTime, actualTime: nil) {
                    images.append(image)
                }
            }
            if !images.isEmpty {
                self.cache.store(encodeStrip(images), base: base, ext: "strip")
            }
            DispatchQueue.main.async { completion(images) }
        }
    }

    private func encodeStrip(_ images: [CGImage]) -> Data {
        // pack into one JPEG with each frame at width 32 (fixed height-normalized) row-wise
        let rowHeight = 36
        let w = max(8, min(40, Int(images[0].width * rowHeight / images[0].height)))
        guard let ctx = CGContext(data: nil, width: w * images.count, height: rowHeight,
                                  bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            return Data()
        }
        ctx.setFillColor(CGColor(gray: 0, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: w * images.count, height: rowHeight))
        for (i, img) in images.enumerated() {
            guard let ptr = ctx.data else { continue }
            _ = ptr
            ctx.interpolationQuality = .medium
            ctx.draw(img, in: CGRect(x: i * w, y: 0, width: w, height: rowHeight))
        }
        guard let strip = ctx.makeImage() else { return Data() }
        let ui = UIImage(cgImage: strip)
        return ui.jpegData(compressionQuality: 0.6) ?? Data()
    }

    private func decodeStrip(_ data: Data) -> [CGImage]? {
        guard let ui = UIImage(data: data), let cg = ui.cgImage else { return nil }
        let w = cg.width, h = cg.height
        // frame width heuristic: strips are <= 40 px per frame
        let frameW = Int(round(Float(h) * 0.75))
        let count = w / max(1, frameW)
        guard count > 0 else { return nil }
        var images: [CGImage] = []
        for i in 0..<count {
            if let cropped = cg.cropping(to: CGRect(x: i * frameW, y: 0, width: frameW, height: h)) {
                images.append(cropped)
            }
        }
        return images
    }
}

/// Waveform extraction: reads a mono PCM downmix via AVAssetReader in the background.
public final class WaveformService {
    public static let shared = WaveformService()

    public func waveform(uri: String) async -> AudioWaveform? {
        await Task.detached(priority: .utility) { () -> AudioWaveform? in
            guard let url = URL(string: uri) else { return nil }
            let asset = AVURLAsset(url: url)
            guard let track = try? await asset.loadTracks(withMediaType: .audio).first else {
                return nil
            }
            guard let reader = try? AVAssetReader(asset: asset) else { return nil }
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatLinearPCM,
                AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false,
                AVLinearPCMIsNonInterleaved: false,
            ]
            let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return nil }
            reader.add(output)
            reader.startReading()
            var samples: [Float] = []
            let bucket = KTime(milliseconds: 16)
            while let sample = output.copyNextSampleBuffer() {
                guard let data = CMSampleBufferGetDataBuffer(sample) else { continue }
                var ptr: UnsafeMutablePointer<Int8>?
                var len: Int = 0
                CMBlockBufferGetDataPointer(data, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &len, dataPointerOut: &ptr)
                guard let p = ptr else { continue }
                let raw = p.withMemoryRebound(to: Int16.self, capacity: len / 2) { buf -> [Int16] in
                    Array(UnsafeBufferPointer(start: buf, count: len / 2))
                }
                for v in raw {
                    samples.append(Float(v) / 32768.0)
                }
            }
            let wf = AudioWaveform.fromSamples(samples, sampleRate: 44100, bucketDuration: bucket)
            return wf
        }.value
    }
}
