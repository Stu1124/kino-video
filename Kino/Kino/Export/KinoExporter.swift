import AVFoundation
import Foundation
import KinoEngine

/// Deterministic high-quality export. Uses the exact same composition +
/// custom compositor as the preview (WYSIWYG guarantee), rendered serially
/// at export resolution with the selected frame rate.
final class KinoExporter {
    enum ExportError: Error {
        case cancelled
        case buildFailed
    }

    private var currentTask: Task<Void, Never>?
    private let progressPump = ProgressPump()

    func cancel() {
        currentTask?.cancel()
    }

    func export(project: KinoProject,
                scale: Float,
                fps: Rational,
                onProgress: @escaping (Double, String) -> Void) async throws -> URL {
        let t0 = Date()
        onProgress(0, "Rendering composition")

        let model = try CompositionFactory.build(project: project, renderScale: scale, fps: fps)
        let videoComp = model.videoComposition
        let canvasSize = project.canvas.renderSize
        videoComp.frameDuration = CMTime(value: CMTimeValue(fps.den), timescale: CMTimeScale(fps.num * 1))
        videoComp.renderSize = CGSize(width: CGFloat(canvasSize.x) * CGFloat(scale),
                                      height: CGFloat(canvasSize.y) * CGFloat(scale))

        CanvasRenderer.uriResolver = { id in project.asset(id)?.uri }

        let outURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KinoExport-\(UUID().uuidString.prefix(8)).mov")

        guard let session = AVAssetExportSession(asset: model.asset, presetName: AVAssetExportPresetHighestQuality) else {
            throw ExportError.buildFailed
        }
        session.outputURL = outURL
        session.outputFileType = .mov
        session.videoComposition = videoComp
        session.audioMix = model.audioMix
        session.shouldOptimizeForNetworkUse = false

        let t = Task {
            // pump progress
            while !Task.isCancelled {
                await MainActor.run {
                    onProgress(Double(session.progress), "Exporting \(Int(session.progress * 100))%")
                }
                try? await Task.sleep(nanoseconds: 250_000_000)
            }
        }
        currentTask = t

        let semaphore = DispatchSemaphore(value: 0)
        var resultError: Error?
        session.exportAsynchronously {
            semaphore.signal()
        }
        // block-await on a background thread so cancellation stays responsive
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                semaphore.wait()
                cont.resume()
            }
        }
        t.cancel()
        let elapsed = Date().timeIntervalSince(t0)
        _ = elapsed

        if taskCancelled, let _ = currentTask {
            try? FileManager.default.removeItem(at: outURL)
            throw ExportError.cancelled
        }
        switch session.status {
        case .completed:
            onProgress(1, "Complete")
            return outURL
        default:
            throw resultError ?? ExportError.buildFailed
        }
    }

    private var taskCancelled: Bool { (currentTask as? Task<Void, Never>)?.isCancelled ?? false }
}

private final class ProgressPump: NSObject {
    func start(_ tick: @escaping () -> Void) -> Timer? {
        let t = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in tick() }
        return t
    }
}
