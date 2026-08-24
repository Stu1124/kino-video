import AVFoundation
import Foundation
import KinoEngine
import SwiftUI

/// Horizontal multi-track timeline with pinch zoom, scroll, clip drag, edge trim,
/// snapping and scrub. State lives in the engine; this view maps gestures → ops.
struct TimelineView: View {
    @ObservedObject var sync: SyncSession

    // zoom / scroll state
    @State private var ppx: CGFloat = 1.0            // pixels per second
    @State private var scrollTarget: CGFloat = 0     // content offset x (pt)
    @State private var contentWidth: CGFloat = 0

    // gesture state
    @State private var dragClipID: UUID?
    @State private var dragMode: DragMode = .none
    @GestureState private var isZooming = false

    enum DragMode {
        case none, move, trimStart, trimEnd
    }

    var body: some View {
        GeometryReader { geo in
            ScrollViewReader { scroller in
                ScrollView(.horizontal, showsIndicators: false) {
                    VStack(spacing: 4) {
                        ruler
                        tracksStack(width: contentWidth)
                    }
                    .frame(width: contentWidth, alignment: .leading)
                    .frame(minHeight: 260)
                    .background(KinoTheme.ink1)
                }
                .coordinateSpace(name: "timeline")
                .onAppear {
                    contentWidth = max(geo.size.width * 1.4, CGFloat(max(projectDuration, KTime(seconds: 10)).seconds) * ppx)
                }
            }
        }
        .onChange(of: sync.projectChangedTick) { _ in
            contentWidth = max(scrollWidth(), contentWidth)
        }
    }

    private func scrollWidth() -> CGFloat {
        CGFloat(max(projectDuration, KTime(seconds: 8)).seconds) * ppx + 120
    }

    private var projectDuration: KTime {
        sync.session.project.duration
    }

    // MARK: ruler

    private var ruler: some View {
        ZStack(alignment: .leading) {
            // marks per second
            HStack(spacing: 0) {
                ForEach(0..<Int(min(projectDuration.seconds, 1800)) + 1, id: \.self) { s in
                    VStack(spacing: 2) {
                        Rectangle().fill(KinoTheme.textTertiary.opacity(0.7)).frame(width: 1, height: s % 5 == 0 ? 9 : 5)
                        if s % 5 == 0 {
                            Text("\(s)s").font(.system(size: 9)).foregroundStyle(KinoTheme.textTertiary)
                        }
                    }
                    .frame(width: ppx, alignment: .center)
                }
            }
            .frame(width: contentWidth, alignment: .leading)
            .frame(height: 26)

            playheadLine(height: 182)
        }
        .frame(height: 26)
        .contentShape(Rectangle())
        .gesture(rulerDragGesture)
    }

    // MARK: tracks

    private func tracksStack(width: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array(sync.session.project.tracks.enumerated()), id: \.element.id) { ti, track in
                trackRow(trackIndex: ti, track: track, width: width)
            }
            addRow
        }
    }

    private func trackRow(trackIndex: Int, track: Track, width: CGFloat) -> some View {
        ZStack(alignment: .leading) {
            Rectangle().fill(KinoTheme.ink1)
            Text(track.name)
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(KinoTheme.textTertiary)
                .padding(.leading, 6)
                .padding(.top, 2)
                .frame(maxHeight: .infinity, alignment: .topLeading)
                .allowsHitTesting(false)

            ForEach(Array(track.clips.enumerated()), id: \.element.id) {_, clip in
                clipCell(clip: clip, track: track, trackIndex: trackIndex, width: width)
            }
        }
        .frame(width: width, height: 44)
    }

    private func clipCell(clip: Clip, track: Track, trackIndex: Int, width: CGFloat) -> some View {
        let x = CGFloat(clip.start.seconds) * ppx
        let w = max(10, CGFloat(clip.duration.seconds) * ppx)
        return ClipCellView(clip: clip, sync: sync, ppx: ppx)
            .frame(width: w, height: 40)
            .overlay(alignment: .leading) { trimHandle(.trimStart, clip: clip, trackIndex: trackIndex) }
            .overlay(alignment: .trailing) { trimHandle(.trimEnd, clip: clip, trackIndex: trackIndex) }
            .offset(x: x)
            .gesture(clipTapGesture(clip: clip, track: track))
            .simultaneousGesture(clipDragGesture(clip: clip, track: track, trackIndex: trackIndex))
            .zIndex(sync.session.selectedClipID == clip.id ? 2 : 1)
    }

    // MARK: handles

    private func trimHandle(_ edge: DragMode, clip: Clip, trackIndex: Int) -> some View {
        Rectangle()
            .fill(KinoTheme.ink4)
            .frame(width: 14)
            .contentShape(Rectangle().inset(by: -10))
            .onTapGesture { _ in
                sync.session.select(clip.id)
            }
            .gesture(trimDragGesture(edge: edge, clip: clip, trackIndex: trackIndex))
    }

    // MARK: gestures

    private func timeDelta(_ translation: CGFloat) -> KTime {
        KTime(seconds: Double(translation) / Double(ppx))
    }

    private func clipTapGesture(clip: Clip, track: Track) -> some Gesture {
        TapGesture().onEnded {
            sync.session.select(clip.id)
        }
    }

    private func clipDragGesture(clip: Clip, track: Track, trackIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 8)
            .onChanged { g in
                if dragClipID != clip.id {
                    sync.session.select(clip.id)
                    dragClipID = clip.id
                    dragMode = .move
                    sync.session.coalescingKey = "move.\(clip.id)"
                }
                guard dragMode == .move else { return }
                let delta = timeDelta(g.translation.width)
                let target = clip.start + delta
                let clamped = KTime.min(KTime.max(target, .zero), sync.session.project.duration + KTime(seconds: 2))
                sync.session.perform("Move") { p in
                    try! EditOps.moveClip(clip.id, to: clamped, &p)
                }
            }
            .onEnded { _ in
                dragClipID = nil
                dragMode = .none
                sync.session.coalescingKey = nil
            }
    }

    private func trimDragGesture(edge: DragMode, clip: Clip, trackIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { g in
                if dragClipID != clip.id {
                    sync.session.select(clip.id)
                    dragClipID = clip.id
                    dragMode = edge
                    sync.session.coalescingKey = "trim.\(clip.id).\(edge == .trimStart ? "l" : "r")"
                }
                guard dragMode == edge else { return }
                let delta = timeDelta(g.translation.width)
                let ripple = trackIndex == 0
                if edge == .trimStart {
                    sync.session.perform("Trim") { p in
                        _ = try? EditOps.trimLeft(clip.id, bySource: delta.scaled(by: Float(1.0 / Double(clip.speed.rate))), ripple: ripple, &p)
                    }
                } else {
                    sync.session.perform("Trim") { p in
                        _ = try? EditOps.trimRight(clip.id, bySource: delta.scaled(by: Float(1.0 / Double(clip.speed.rate))), ripple: ripple, &p)
                    }
                }
            }
            .onEnded { _ in
                dragClipID = nil
                dragMode = .none
                sync.session.coalescingKey = nil
            }
    }

    private var rulerDragGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { g in
                sync.isScrubbingPreview = true
                let tm = timeAt(localX: g.location.x)
                sync.setPlayhead(tm)
            }
            .onEnded { _ in
                sync.isScrubbingPreview = false
            }
    }

    private func timeAt(localX x: CGFloat) -> KTime {
        let t = Double(x) / Double(ppx)
        return KTime(seconds: max(0, t))
    }

    // MARK: playhead

    @ViewBuilder
    private func playheadLine(height: CGFloat) -> some View {
        let x = CGFloat(sync.currentTime.seconds) * ppx
        ZStack {
            VStack(spacing: 4) {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 9))
                    .rotationEffect(.degrees(180))
                Rectangle().fill(KinoTheme.textPrimary).frame(width: 2)
            }
            .frame(width: 18, height: height, alignment: .top)
        }
        .offset(x: x - 9)
        .allowsHitTesting(false)
    }

    private var addRow: some View {
        HStack {
            Button { } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                    Text("Add clips, audio, text").font(.system(size: 12))
                }
                .foregroundStyle(KinoTheme.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(KinoTheme.ink2, in: Capsule())
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.horizontal, 10)
        .frame(height: 44)
    }
}

// MARK: - Clip cell

struct ClipCellView: View {
    let clip: Clip
    @ObservedObject var sync: SyncSession
    let ppx: CGFloat
    @State private var fibers: [CGImage] = []

    var body: some View {
        ZStack {
            thumbnailStrip
            clipCaption
        }
        .background(clipColor)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(borderColor, lineWidth: 2)
        )
        .task(id: taskID) {
            loadFibers()
        }
    }

    private var borderColor: Color {
        sync.session.selectedClipID == clip.id ? KinoTheme.accent : Color.clear
    }

    private var taskID: String {
        let aid = clip.assetID?.uuidString ?? clip.id.uuidString
        return "\(aid)-\(clip.sourceRange.start.ns)-\(clip.sourceRange.end.ns)"
    }

    private func loadFibers() {
        guard clip.kind == .video || clip.kind == .image else { return }
        guard let uri = urlStringForAsset else { return }
        if clip.kind == .video {
            let frames = min(20, max(4, Int(CGFloat(clip.duration.seconds) * ppx / 26)))
            ThumbnailService.shared.filmstrip(uri: uri, sourceRange: clip.sourceRange, duration: clip.duration, frames: frames) { images in
                fibers = images
            }
        } else {
            ThumbnailService.shared.thumbnail(targetSize: CGSize(width: 120, height: 120), uri: uri, at: clip.sourceRange.start) { img in
                if let img { fibers = [img] }
            }
        }
    }

    private var clipCaption: some View {
        VStack {
            Spacer()
            HStack {
                Image(systemName: icon).font(.system(size: 8)).foregroundStyle(.white.opacity(0.9))
                Text(clip.name).lineLimit(1).font(.system(size: 8, weight: .medium)).foregroundStyle(.white.opacity(0.9))
                Spacer()
            }
            .padding(3)
            .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 3))
        }
        .padding(2)
    }

    private var urlStringForAsset: String? {
        sync.session.project.asset(clip.assetID ?? UUID())?.uri
    }

    private var clipColor: Color {
        switch clip.kind {
        case .video, .image: return .clear
        case .audio: return Color(hex: 0x2F3A8C).opacity(0.75)
        case .text: return KinoTheme.accent.opacity(0.55)
        case .sticker: return Color(hex: 0xB45BB0).opacity(0.55)
        }
    }

    private var icon: String {
        switch clip.kind {
        case .video: return "video.fill"
        case .image: return "photo.fill"
        case .audio: return "waveform"
        case .text: return "textformat"
        case .sticker: return "star.fill"
        }
    }

    @ViewBuilder
    private var thumbnailStrip: some View {
        if !fibers.isEmpty {
            HStack(spacing: 0) {
                ForEach(0..<fibers.count, id: \.self) { i in
                    Image(decorative: fibers[i], scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                        .frame(height: 40)
                        .clipped()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Rectangle().fill(clip.kind == .audio ? Color(hex: 0x2F3A8C) : KinoTheme.ink3)
        }
    }
}
