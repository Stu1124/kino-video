import AVFoundation
import Foundation
import Photos
import PhotosUI
import KinoEngine

/// Imports PHAsset media into the app's library folder (copy semantics — durable).
public final class MediaImporter: ObservableObject {
    @Published public var progress: ImportProgress?

    public struct ImportProgress {
        public var completed: Int
        public var total: Int
        public var phase: String
    }

    public enum ImportError: Error {
        case unsupported, cancelled
    }

    private let libraryURL: URL

    public init(libraryURL: URL? = nil) {
        self.libraryURL = libraryURL ?? FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Media", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.libraryURL, withIntermediateDirectories: true)
    }

    private var assetCache: UUID = UUID()

    /// Imports photo/asset identifiers. Returns created MediaAssets or throws.
    @discardableResult
    public func importAssets(identifiers: [String]) async throws -> [MediaAsset] {
        var out: [MediaAsset] = []
        progress = ImportProgress(completed: 0, total: identifiers.count, phase: "Importing")
        defer { progress = nil }
        let cache = assetCache
        for (i, id) in identifiers.enumerated() {
            guard cache == assetCache else { throw ImportError.cancelled }
            progress?.completed = i
            if let asset = try await importOne(identifier: id) {
                out.append(asset)
            }
            progress?.completed = i + 1
        }
        return out
    }

    public func cancel() {
        assetCache = UUID()
    }

    private func importOne(identifier: String) async throws -> MediaAsset? {
        guard let ph = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject else { return nil }
        let fm = FileManager.default
        var target: URL?
        var name = ph.localIdentifier.replacingOccurrences(of: "/", with: "_")
        name = "asset-\(name).\(ph.mediaType == .video ? "mov" : "jpg")"

        switch ph.mediaType {
        case .video:
            let resources = PHAssetResource.assetResources(for: ph)
            guard let resource = resources.first else { return nil }
            let ext = resource.uniformTypeIdentifier?.split(separator: ".").last.map(String.init) ?? "mov"
            name = "asset-\(UUID().uuidString.prefix(12)).\(ext)"
            target = libraryURL.appendingPathComponent(name)
            try await copyResource(resource, to: target!)
        case .image:
            let resources = PHAssetResource.assetResources(for: ph)
            guard let resource = resources.first else { return nil }
            let targetName = "image-\(UUID().uuidString.prefix(12)).jpg"
            target = libraryURL.appendingPathComponent(targetName)
            try await copyResource(resource, to: target!)
        default:
            return nil
        }

        guard let url = target else { return nil }
        var asset: MediaAsset
        if ph.mediaType == .video {
            let metadata = try await videoMetadata(url: url)
            asset = MediaAsset(uri: url.absoluteString, kind: .video,
                               name: ph.localIdentifier.hasPrefix("IMG") ? "Photo" : "Video",
                               resolution: metadata.size, duration: metadata.duration,
                               fps: metadata.fps, audioTrackPresent: metadata.hasAudio)
        } else {
            let size = try? await imageSize(url: url)
            asset = MediaAsset(uri: url.absoluteString, kind: .image, name: "Image",
                               resolution: size.flatMap { KVec2(Float($0.width), Float($0.height)) })
        }
        return asset
    }

    private func copyResource(_ resource: PHAssetResource, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let opts = PHAssetResourceRequestOptions()
            opts.isNetworkAccessAllowed = true
            PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: opts) { error in
                if let error { cont.resume(throwing: error) } else { cont.resume() }
            }
        }
    }

    struct VideoMetadata {
        var size: KVec2
        var duration: KTime
        var fps: Float?
        var hasAudio: Bool
    }

    private func videoMetadata(url: URL) async throws -> VideoMetadata {
        try await Task.detached {
            let asset = AVURLAsset(url: url)
            let tracks = try await asset.loadTracks(withMediaType: .video)
            guard let track = tracks.first else { throw ImportError.unsupported }
            let size = try await track.load(.naturalSize)
            let transform = try await track.load(.preferredTransform)
            // apply aspect-preserving transform
            var natural = size
            if transform.a == 0 && transform.b == 1 && transform.c == -1 {
                natural = CGSize(width: size.height, height: size.width)
            }
            let duration = try await asset.load(.duration)
            let fps = try await track.load(.nominalFrameRate)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)
            return VideoMetadata(size: KVec2(Float(natural.width), Float(natural.height)),
                                 duration: KTime(duration),
                                 fps: fps > 0 ? Float(fps) : nil,
                                 hasAudio: !audioTracks.isEmpty)
        }.value
    }

    private func imageSize(url: URL) async throws -> CGSize {
        try await Task.detached {
            guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
                  let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] else {
                return CGSize(width: 1920, height: 1920)
            }
            let w = (props[kCGImagePropertyPixelWidth] as? CGFloat) ?? 1920
            let h = (props[kCGImagePropertyPixelHeight] as? CGFloat) ?? 1920
            return CGSize(width: w, height: h)
        }.value
    }
}
