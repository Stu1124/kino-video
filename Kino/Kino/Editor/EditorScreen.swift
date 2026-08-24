import AVKit
import Foundation
import KinoEngine
import PhotosUI
import SwiftUI

struct EditorScreen: View {
    let projectID: UUID
    @StateObject private var store = ProjectStore()
    @StateObject private var preview = PreviewEngine()
    @StateObject private var sync: SyncSession
    @Environment(\.dismiss) private var dismiss

    @State private var showPicker = false
    @State private var showExport = false
    @State private var pendingIdentifiers: [String] = []
    @State private var importer = MediaImporter()
    @State private var importing = false
    @State private var confirmingExit = false

    init(projectID: UUID) {
        self.projectID = projectID
        if let project = ProjectStore().load(projectID) {
            _sync = StateObject(wrappedValue: SyncSession(project: project, store: ProjectStore(), preview: PreviewEngine.shared))
        } else {
            _sync = StateObject(wrappedValue: SyncSession(project: KinoProject(), store: ProjectStore(), preview: PreviewEngine.shared))
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            previewArea
            toolRail
            TimelineView(sync: sync)
                .frame(height: 300)
        }
        .background(KinoTheme.backgroundColor)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            sync.bootstrapPreview(time: sync.session.playhead)
        }
        .onChange(of: sync.currentTime) { t in
            if !preview.playing {
                // keep playhead in sync when user scrubbed on timeline
            }
        }
        .onDisappear {
            sync.flushSave()
        }
        .sheet(isPresented: $showPicker) {
            KinoMediaPicker { ids in
                pendingIdentifiers = ids
                importMedia()
            }
        }
        .fullScreenCover(isPresented: $showExport) {
            ExportView(sync: sync, store: store)
        }
        .alert("Leave editor?", isPresented: $confirmingExit) {
            Button("Save & Leave") {
                sync.flushSave()
                dismiss()
            }
            Button("Discard") {
                // reload from disk to discard unsaved session state
                dismiss()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Your changes are autosaved when leaving.")
        }
    }

    // MARK: top bar

    private var topBar: some View {
        HStack(spacing: 12) {
            Button {
                if sync.isDirty {
                    confirmingExit = true
                } else {
                    dismiss()
                }
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(KinoTheme.textPrimary)
                    .frame(width: 34, height: 34)
                    .background(KinoTheme.ink2, in: Circle())
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 1) {
                Text(sync.session.project.meta.name)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(KinoTheme.textPrimary)
                Text(formatTime(sync.currentTime))
                    .font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(KinoTheme.textSecondary)
            }
            Spacer()
            undoRedo
            Button {
                showExport = true
            } label: {
                Text("Export")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(KinoTheme.accentGradient, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }

    private var undoRedo: some View {
        HStack(spacing: 6) {
            Button { sync.undo() } label: {
                Image(systemName: "arrow.uturn.backward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(sync.canUndo ? KinoTheme.textPrimary : KinoTheme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(KinoTheme.ink2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!sync.canUndo)
            Button { sync.redo() } label: {
                Image(systemName: "arrow.uturn.forward")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(sync.canRedo ? KinoTheme.textPrimary : KinoTheme.textTertiary)
                    .frame(width: 32, height: 32)
                    .background(KinoTheme.ink2, in: Circle())
            }
            .buttonStyle(.plain)
            .disabled(!sync.canRedo)
        }
    }

    // MARK: preview

    private var previewArea: some View {
        CanvasPreviewView(sync: sync, preview: preview)
            .frame(maxWidth: .infinity)
            .background(KinoTheme.ink0)
    }

    // MARK: tool rail

    private var toolRail: some View {
        HStack(spacing: 14) {
            toolButton("photo.badge.plus", "Add Media") { showPicker = true }
            toolButton("textformat", "Text") { setTool(.text) }
            toolButton("waveform", "Audio") { setTool(.volume) }
            toolButton("speedometer", "Speed") { setTool(.speed) }
            toolButton("slider.horizontal.3", "Adjust") { setTool(.filters) }
            toolButton("sparkles", "Effects") { setTool(.effects) }
            toolButton("square.2.layers.3d.top.filled", "Transitions") { setTool(.transitions) }
            toolButton("crop.and.scale", "Transform") { setTool(.transform) }
            toolButton("arrow.3.trianglepath", "Masks") { setTool(.masks) }
            toolButton("diamond.fill", "Keyframes") { setTool(.keyframes) }
            toolButton("character.cursor.ibeam", "Captions") { setTool(.captions) }
            toolButton("aspectratio", "Canvas") { setTool(.canvas) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(KinoTheme.ink1)
        .snapToCenter(axis: .horizontal)
    }

    private func toolButton(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon).font(.system(size: 15, weight: .medium))
                Text(label).font(.system(size: 9))
            }
            .foregroundStyle(activeTool == label ? KinoTheme.textPrimary : KinoTheme.textSecondary)
            .frame(width: 52)
            .padding(.vertical, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(activeTool == label ? KinoTheme.ink3 : Color.clear))
        }
        .buttonStyle(.plain)
    }

    private var activeTool: String? {
        ["Text": sync.selectedTool == .text,
         "Audio": sync.selectedTool == .volume || sync.selectedTool == .transform].first { $0.value }?.key
    }

    private func setTool(_ tool: EditorTool) {
        sync.selectedTool = tool
    }

    private func importMedia() {
        guard !pendingIdentifiers.isEmpty else { return }
        importing = true
        Task {
            defer { importing = false }
            let added = (try? await importer.importAssets(identifiers: pendingIdentifiers)) ?? []
            guard !added.isEmpty else { return }
            let session = sync.session
            var newAssets = session.project.assets
            newAssets.append(contentsOf: added.filter { a in !newAssets.contains { $0.id == a.id } })
            session.perform("Add Media") { p in
                p.assets = newAssets
                // add clips to main track for each video
                var clips = p.tracks[0].clips
                let start = p.duration
                for asset in added where asset.kind == .video {
                    let c = Clip(name: asset.name, kind: .video, assetID: asset.id,
                                 start: start, sourceRange: TimeRange(start: .zero, duration: asset.duration ?? KTime(seconds: 5)))
                    clips.append(c)
                }
                for asset in added where asset.kind == .image {
                    let c = Clip(name: asset.name, kind: .image, assetID: asset.id,
                                 start: start, sourceRange: TimeRange(start: .zero, duration: KTime(seconds: 4)))
                    clips.append(c)
                }
                clips.sort { $0.start.ns < $1.start.ns }
                p.tracks[0].clips = clips
            }
            session.selectClip(at: session.playhead)
        }
    }

    private func formatTime(_ t: KTime) -> String {
        let total = Int(t.seconds)
        return String(format: "%02d:%02d.%02d", total / 60, total % 60, Int((t.seconds - Double(total)) * 100))
    }
}

private extension View {
    func snapToCenter(axis _: Axis) -> some View { self }
}

// MARK: - Canvas preview with direct manipulation

struct CanvasPreviewView: View {
    @ObservedObject var sync: SyncSession
    @ObservedObject var preview: PreviewEngine
    @State private var viewSize: CGSize = .zero
    @State private var dragStartCenter: KVec2?
    @State private var dragStartScale: Float = 1
    @State private var dragStartRotation: Float = 0
    @State private var gesturePhase = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                PlayerSurface(player: preview.player)
                    .aspectRatio(CGFloat(sync.session.project.canvas.aspect), contentMode: .fit)
                    .clipped()
                    .background(.black)
                    .onAppear { viewSize = geo.size }
                overlayManipulationUI
                playPauseButton
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var selectedLayerFrame: LayerFrame? {
        guard let clip = sync.session.selectedClip else { return nil }
        return RenderTree.frame(for: clip, at: sync.currentTime)
    }

    @ViewBuilder
    private var overlayManipulationUI: some View {
        if let frame = selectedLayerFrame, gesturePhase == false {
            BoxedOverlayView(frame: frame, canvasAspect: sync.session.project.canvas.aspect)
        }
    }

    private var playPauseButton: some View {
        Button {
            sync.togglePlay()
        } label: {
            ZStack {
                Circle().fill(.black.opacity(0.4)).frame(width: 58, height: 58)
                Image(systemName: preview.playing ? "pause.fill" : "play.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .padding(14)
    }
}

// MARK: - Player surface

final class PlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    init(player: AVPlayer) { self.player = player }

    func makeUIView(context: Context) -> AVPlayerLayerView {
        let v = AVPlayerLayerView()
        v.player = player
        v.videoGravity = .resizeAspect
        return v
    }

    func updateUIView(_ view: AVPlayerLayerView, context: Context) {
        view.player = player
    }
}

final class AVPlayerLayerView: UIView {
    var player: AVPlayer? {
        get { (layer as! AVPlayerLayer).player }
        set { (layer as! AVPlayerLayer).player = newValue }
    }
    var videoGravity: AVLayerVideoGravity {
        get { (layer as! AVPlayerLayer).videoGravity }
        set { (layer as! AVPlayerLayer).videoGravity = newValue }
    }
    override class var layerClass: AnyClass { AVPlayerLayer.self }
}

// MARK: - overlay selection box

struct BoxedOverlayView: View {
    let frame: LayerFrame
    let canvasAspect: Float

    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let canvas2 = KVec2(Float(size.width), Float(size.height))
            let scaleBase = KFitMath.fillScale(asset: frame.assetSize ?? KVec2(1, 1),
                                               canvas: canvas2) * frame.transform.scale
            let cw = CGFloat(frame.assetSize?.x ?? 1) * scaleBase
            let ch = CGFloat(frame.assetSize?.y ?? 1) * scaleBase
            let cx = frame.transform.center.x * size.width
            let cy = frame.transform.center.y * size.height
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(KinoTheme.accent, style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                dot(.topLeading)
                dot(.topTrailing)
                dot(.bottomLeading)
                dot(.bottomTrailing)
                Circle().fill(KinoTheme.accent).frame(width: 6, height: 6).offset(y: -ch / 2 - 8)
            }
            .frame(width: cw, height: ch)
            .rotationEffect(.degrees(Double(frame.transform.rotation)))
            .position(x: cx, y: cy)
            .allowsHitTesting(false)
        }
    }

    private func dot(_ corner: Alignment) -> some View {
        Circle().fill(KinoTheme.textPrimary).frame(width: 8, height: 8).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
    }
}
