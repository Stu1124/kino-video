import Combine
import Foundation
import KinoEngine

/// ObservableEditorSession adapts the engine's EditorSession to SwiftUI:
/// publishes events, autosaves on change, and tracks the tool selection.
final class SyncSession: ObservableObject {
    let session: EditorSession
    @Published var projectChangedTick = 0
    @Published var selectionTick = 0
    @Published var undoRedoTick = 0
    @Published var currentTime: KTime = .zero
    @Published var selectedTool: EditorTool = .none
    @Published var isDirty = false
    @Published var isScrubbingPreview = false

    private var store: ProjectStore
    private var autosaveTask: Task<Void, Never>?
    private var cancellables: [AnyCancellable] = []
    private var pipeline: PreviewEngine?

    private let eventsSubject = PassthroughSubject<EditorEvent, Never>()

    init(project: KinoProject, store: ProjectStore, preview: PreviewEngine? = nil) {
        self.session = EditorSession(project: project, subject: eventsSubject)
        self.store = store
        self.pipeline = preview
        eventsSubject.receive(on: DispatchQueue.main)
            .sink { [weak self] event in
                guard let self else { return }
                switch event {
                case .projectChanged:
                    self.projectChangedTick += 1
                    self.isDirty = true
                    self.scheduleAutosave()
                    self.refreshPreview()
                case .playheadChanged:
                    self.currentTime = self.session.playhead
                case .selectionChanged:
                    self.selectionTick += 1
                    self.selectedTool = self.defaultToolForSelection
                case .undoRedoChanged:
                    self.undoRedoTick += 1
                    self.isDirty = true
                case .undoApplied, .redoApplied:
                    self.projectChangedTick += 1
                    self.isDirty = true
                    self.scheduleAutosave()
                    self.refreshPreview()
                case .mediaLibraryChanged:
                    self.projectChangedTick += 1
                }
            }
            .store(in: &cancellables)
    }

    private var defaultToolForSelection: EditorTool {
        guard let selected = session.selectedClip else { return .none }
        return .transform
    }

    // MARK: playhead binding

    func setPlayhead(_ t: KTime) {
        session.playhead = t
        pipeline?.seek(t)
    }

    func play() { pipeline?.play() }
    func pause() { pipeline?.pause() }
    var isPlaying: Bool { pipeline?.playing ?? false }

    func togglePlay() {
        guard let pipeline else { return }
        pipeline.togglePlay()
    }

    private func refreshPreview() {
        pipeline?.rebuild(project: session.project)
    }

    /// Initial content build (first launch of an editor).
    func bootstrapPreview(time: KTime) {
        pipeline?.rebuild(project: session.project, keepTime: false)
        pipeline?.seek(time)
    }

    // MARK: Undo/redo

    func undo() { session.undo() }
    func redo() { session.redo() }
    var canUndo: Bool { session.canUndo }
    var canRedo: Bool { session.canRedo }

    // MARK: Autosave

    private func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled, let self else { return }
            await MainActor.run {
                subjectStateForSave()
            }
        }
    }

    func subjectStateForSave() {
        var p = session.project
        p.lastPlayhead = session.playhead
        p.lastSelectedClipID = session.selectedClipID
        p.meta.modifiedAt = Date()
        try? store.save(p)
        store.reloadIndex()
        isDirty = false
    }

    func flushSave() {
        autosaveTask?.cancel()
        subjectStateForSave()
    }
}

extension EditorSession {
    /// Route events into a Combine subject for SwiftUI observation.
    convenience init(project: KinoProject, subject: PassthroughSubject<EditorEvent, Never>) {
        self.init(project: project, notify: { subject.send($0) })
    }
}

enum EditorTool: String, CaseIterable {
    case none
    case transform
    case trim
    case split
    case speed
    case volume
    case filters
    case effects
    case text
    case captions
    case transitions
    case keyframes
    case masks
    case animations
    case chromakey
    case canvas
    case stickers
}
