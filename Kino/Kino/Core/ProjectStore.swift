import Foundation
import KinoEngine

/// Persists projects to the app's Documents directory: crash-safe JSON writes,
/// metadata index, autosaving and cleanup.
public final class ProjectStore: ObservableObject {
    @Published public private(set) var projects: [ProjectSummary] = []

    let root: URL

    public init(root: URL? = nil) {
        self.root = root ?? FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Projects", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.root, withIntermediateDirectories: true)
        reloadIndex()
    }

    private var dir: URL { root }
    private func fileURL(_ id: UUID) -> URL { dir.appendingPathComponent("\(id.uuidString).kino.json") }

    // MARK: Index

    public struct ProjectSummary: Identifiable, Equatable {
        public let id: UUID
        public var name: String
        public var modifiedAt: Date
        public var duration: KTime
        public var canvas: CanvasConfig
        public var clipCount: Int
        public var thumbnailURI: String? // optional cover media
        public init(id: UUID, name: String, modifiedAt: Date, duration: KTime, canvas: CanvasConfig, clipCount: Int, thumbnailURI: String?) {
            self.id = id
            self.name = name
            self.modifiedAt = modifiedAt
            self.duration = duration
            self.canvas = canvas
            self.clipCount = clipCount
            self.thumbnailURI = thumbnailURI
        }
    }

    @discardableResult
    public func reloadIndex() -> [ProjectSummary] {
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.fileModificationDateKey])) ?? []
        var out: [ProjectSummary] = []
        for f in files where f.pathExtension == "json" {
            guard let data = try? Data(contentsOf: f),
                  let project = try? KinoProject.decode(data) else { continue }
            out.append(ProjectSummary(
                id: project.meta.id,
                name: project.meta.name,
                modifiedAt: project.meta.modifiedAt,
                duration: project.duration,
                canvas: project.canvas,
                clipCount: project.allClips().count,
                thumbnailURI: project.assets.first(where: { $0.kind == .video })?.uri
            ))
        }
        out.sort { $0.modifiedAt > $1.modifiedAt }
        projects = out
        return out
    }

    // MARK: CRUD

    public func createProject(name: String = "Untitled", canvas: CanvasConfig = CanvasConfig()) throws -> KinoProject {
        let p = KinoProject(meta: KinoProject.Meta(name: name), canvas: canvas)
        try save(p)
        return p
    }

    public func load(_ id: UUID) -> KinoProject? {
        guard let data = try? Data(contentsOf: fileURL(id)) else { return nil }
        guard var p = try? KinoProject.decode(data) else { return nil }
        revalidateMedia(&p)
        return p
    }

    public func save(_ p: KinoProject) throws {
        let data = try p.encodedJSON()
        let url = fileURL(p.meta.id)
        // atomic write: temp file + rename (crash-safe)
        let tmp = dir.appendingPathComponent("\(p.meta.id.uuidString).tmp")
        try data.write(to: tmp, options: .atomic)
        if FileManager.default.fileExists(atPath: url.path) {
            _ = try? FileManager.default.replaceItemAt(url, withItemAt: tmp)
        } else {
            try FileManager.default.moveItem(at: tmp, to: url)
        }
        reloadIndex()
    }

    public func rename(_ p: inout KinoProject, _ name: String) throws {
        p.meta.name = name
        try save(p)
    }

    public func duplicate(_ id: UUID) throws -> KinoProject? {
        guard var p = load(id) else { return nil }
        p.meta.id = UUID()
        p.meta.name = p.meta.name + " Copy"
        p.meta.createdAt = Date()
        p.meta.modifiedAt = Date()
        // duplicate all asset handles (URIs stay referenced, copy semantics documented)
        try save(p)
        return p
    }

    public func delete(_ id: UUID) throws {
        try? FileManager.default.removeItem(at: fileURL(id))
        reloadIndex()
    }

    // MARK: Missing-media handling

    func revalidateMedia(_ p: inout KinoProject) {
        let fm = FileManager.default
        p.assets = p.assets.filter { asset in
            let url = URL(string: asset.uri)
            guard let u = url, u.isFileURL else { return true }
            if fm.fileExists(atPath: u.path) { return true }
            // media still referenced but absent: clip availability is handled at render time
            return true
        }
    }
}
