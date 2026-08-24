#if DEBUG
import AVFoundation
import Foundation
import UIKit
import KinoEngine

/// Synthesizes media + a sample project on simulator (UI tests, demos).
/// Never runs on a real device unless --fixtures is passed at launch.
public enum FixtureFactory {

    public struct Fixtures {
        public var videoA: URL
        public var videoB: URL
        public var image: URL
        public var audio: URL
        public var projectID: UUID
    }

    /// Generates fixtures off the main thread (watchdog safety). Returns when done.
    public static func ensureAsync() async -> Fixtures? {
        return await Task.detached(priority: .utility) { () -> Fixtures? in
            ensure()
        }.value
    }

    public static func ensure() -> Fixtures? {
        status = "writing media"
        let fm = FileManager.default
        let base = fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Fixtures", isDirectory: true)
        try? fm.createDirectory(at: base, withIntermediateDirectories: true)

        let a = base.appendingPathComponent("fixture-a.mov")
        let b = base.appendingPathComponent("fixture-b.mov")
        let img = base.appendingPathComponent("fixture-img.jpg")
        let wav = base.appendingPathComponent("fixture-tone.wav")

        if !fm.fileExists(atPath: a.path) { writeVideo(url: a, seconds: 2, color: UIColor.systemMint, label: "SUNLIGHT") }
        status = "media A ok"
        if !fm.fileExists(atPath: b.path) { writeVideo(url: b, seconds: 2, color: UIColor.systemOrange, label: "WARM") }
        status = "media B ok"
        if !fm.fileExists(atPath: img.path) { writeImage(url: img) }
        if !fm.fileExists(atPath: wav.path) { writeTone(url: wav, seconds: 4) }
        status = "media done"

        let store = ProjectStore()
        let sampleID = base.appendingPathComponent("fixture-project.json")
        var fixturesHost: UUID? = nil
        status = "saving project"
        if !fm.fileExists(atPath: sampleID.path) {
            fixtures = nil
            var project = KinoProject(meta: .init(name: "Sample Edit"))
            project.assets = [
                MediaAsset(uri: a.absoluteString, kind: .video, name: "Sunlight",
                           resolution: KVec2(640, 360), duration: KTime(seconds: 5),
                           fps: 30, audioTrackPresent: false),
                MediaAsset(uri: b.absoluteString, kind: .video, name: "Warm",
                           resolution: KVec2(640, 360), duration: KTime(seconds: 4),
                           fps: 30, audioTrackPresent: false),
                MediaAsset(uri: img.absoluteString, kind: .image, name: "Cover",
                           resolution: KVec2(800, 600)),
                MediaAsset(uri: wav.absoluteString, kind: .audio, name: "Tone",
                           duration: KTime(seconds: 4), audioTrackPresent: true),
            ]
            let v1 = Clip(name: "Sunlight", kind: .video, assetID: project.assets[0].id, start: .zero,
                          sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 5)),
                          speed: SpeedSpec(rate: 1))
            project.tracks[0].clips = [v1]
            project.tracks.append(Track(kind: .audio, name: "Music", clips: [
                Clip(name: "Tone", kind: .audio, assetID: project.assets[3].id, start: .zero,
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 4)),
                     audio: AudioSpec(volume: 0.5)),
            ]))
            project.tracks.append(Track(kind: .text, name: "Text", clips: [
                Clip(name: "Title", kind: .text, start: KTime(milliseconds: 500),
                     sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 3)),
                     text: {
                         var t = TextContent(string: "Hello Kino")
                         t.fontSize = 0.06
                         return t
                     }()),
            ]))
            try? store.save(project)
            fixturesHost = project.meta.id
        } else if let loaded = try? store.load(UUID(uuidString: "00000000-0000-0000-0000-000000000001")!) {
            fixturesHost = loaded.meta.id
        }
        fixtures = fixturesHost
        status = "done"
        return Fixtures(videoA: a, videoB: b, image: img, audio: wav, projectID: fixturesHost ?? UUID())
    }

    public static var status: String = "not started" {
        didSet { FixtureStatus.shared.status = status }
    }

    public static var fixtures: UUID?

    // MARK: synth media

    private static func writeVideo(url: URL, seconds: Double, color: UIColor, label: String) {
        let fps = 30
        let w = 480, h = 270
        try? FileManager.default.removeItem(at: url)
        status = "\\(label): init writer"
        guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else {
            status = "\\(label): writer init failed"
            return
        }
        let settings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: w,
            AVVideoHeightKey: h,
        ]
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: settings)
        let attrs: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
            kCVPixelBufferWidthKey as String: w,
            kCVPixelBufferHeightKey as String: h,
        ]
        writer.add(input)
        status = "\\(label): startWriting"
        guard writer.startWriting() else {
            status = "\\(label): startWriting failed: \(writer.error?.localizedDescription ?? "?")"
            return
        }
        writer.startSession(atSourceTime: .zero)
        status = "\\(label): encoding"

        let total = Int(seconds * Double(fps))
        var failed = false
        for frame in 0..<total {
            var waited = 0.0
            while !input.isReadyForMoreMediaData {
                usleep(2000)
                waited += 0.002
                if waited > 8 { failed = true; break }
            }
            if failed || writer.status != .writing {
                status = "\\(label): stalled at frame \\(frame), status=\(writer.status.rawValue) err=\(writer.error?.localizedDescription ?? "none")"
                break
            }
            var buf: CVPixelBuffer?
            CVPixelBufferCreate(nil, w, h, kCVPixelFormatType_32ARGB, attrs as CFDictionary, &buf)
            guard let pb = buf else { continue }
            CVPixelBufferLockBaseAddress(pb, [])
            let ctx = CGContext(data: CVPixelBufferGetBaseAddress(pb),
                                width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: CVPixelBufferGetBytesPerRow(pb),
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)
            // animated gradient panel + label
            let phase = CGFloat(frame) / CGFloat(total)
            ctx!.setFillColor(color.withAlphaComponent(0.8).cgColor)
            ctx!.fill(CGRect(x: 0, y: 0, width: w, height: h))
            let grad = CGGradient(colorsSpace: nil, colors: [color.withAlphaComponent(1).cgColor, UIColor.white.withAlphaComponent(0.35).cgColor] as CFArray, locations: [0, 1])!
            ctx!.drawLinearGradient(grad, start: CGPoint(x: 0, y: phase * CGFloat(h)), end: CGPoint(x: CGFloat(w), y: (1 + phase) * CGFloat(h)), options: [])
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            let attrsText: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 54, weight: .bold),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ]
            let str = "\(label)\n\(frame)"
            NSAttributedString(string: str, attributes: attrsText).draw(in: CGRect(x: 0, y: h / 2 - 70, width: w, height: 120))
            // motion bar
            ctx!.setFillColor(UIColor.white.cgColor)
            let slideX = frame * 7 % w
            let slideY = frame * 13 % h
            ctx!.fill(CGRect(x: slideX, y: 0, width: 24, height: 24))
            ctx!.setFillColor(UIColor.systemBlue.cgColor)
            ctx!.fillEllipse(in: CGRect(x: slideX, y: h / 2, width: 30, height: 30))
            ctx!.setFillColor(UIColor.systemYellow.cgColor)
            ctx!.fillEllipse(in: CGRect(x: w / 2, y: slideY, width: 18, height: 18))
            CVPixelBufferUnlockBaseAddress(pb, [])
            let sample = CMSampleBuffer.createFrom(pixelBuffer: pb, time: CMTime(value: CMTimeValue(frame), timescale: CMTimeScale(fps)))
            if let sample {
                input.append(sample)
            }
        }
        input.markAsFinished()
        let finishSem = DispatchSemaphore(value: 0)
        writer.finishWriting { finishSem.signal() }
        let _ = finishSem.wait(timeout: .now() + 20)
    }

    private static func writeImage(url: URL) {
        let size = CGSize(width: 800, height: 600)
        let r = UIGraphicsImageRenderer(size: size)
        let img = r.image { ctx in
            let colors = [UIColor.systemTeal.cgColor, UIColor.systemBlue.cgColor] as CFArray
            let grad = CGGradient(colorsSpace: nil, colors: colors, locations: nil)!
            ctx.cgContext.drawLinearGradient(grad, start: .zero, end: CGPoint(x: size.width, y: size.height), options: [])
            let para = NSMutableParagraphStyle()
            para.alignment = .center
            ("KINO" as NSString).draw(at: CGPoint(x: 300, y: 260), withAttributes: [
                .font: UIFont.systemFont(ofSize: 64, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: para,
            ])
        }
        try? img.jpegData(compressionQuality: 0.9)?.write(to: url)
    }

    private static func writeTone(url: URL, seconds: Double) {
        let sr = 44100.0
        let n = Int(sr * seconds)
        let fileURL = url
        try? FileManager.default.removeItem(at: fileURL)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: sr,
            AVNumberOfChannelsKey: 1,
        ]
        guard let file = try? AVAudioFile(forWriting: fileURL, settings: settings),
              let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(n)),
              let data = buf.floatChannelData else {
            status = "tone: setup failed"
            return
        }
        buf.frameLength = AVAudioFrameCount(n)
        let data0 = data[0]
        for i in 0..<n {
            let t = Double(i) / sr
            let beat = sin(2 * .pi * 440 * t)
            let melody = sin(2 * .pi * 220 * t) * 0.5
            let env = (1 + sin(2 * .pi * 0.5 * t)) * 0.5
            data0[i] = Float((beat + melody) * 0.22 * env)
        }
        try? file.write(from: buf)
    }
}
#endif


extension CMSampleBuffer {
    static func createFrom(pixelBuffer: CVPixelBuffer, time: CMTime) -> CMSampleBuffer? {
        var sample: CMSampleBuffer?
        var timing = CMSampleTimingInfo(duration: CMTime(value: 1, timescale: 30),
                                        presentationTimeStamp: time, decodeTimeStamp: .invalid)
        var format: CMVideoFormatDescription?
        CMVideoFormatDescriptionCreateForImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescriptionOut: &format)
        guard let fmt = format else { return nil }
        CMSampleBufferCreateReadyWithImageBuffer(allocator: nil, imageBuffer: pixelBuffer, formatDescription: fmt,
                                                 sampleTiming: &timing, sampleBufferOut: &sample)
        return sample
    }
}


#if DEBUG
final class FixtureStatus: ObservableObject {
    static let shared = FixtureStatus()
    @Published var status = "not started"
}
#endif
