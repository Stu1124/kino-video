import AVFoundation
import Photos
import SwiftUI
import UIKit
import KinoEngine

/// Export pipeline UI: choose settings, render, save to Photos / share.
struct ExportView: View {
    @ObservedObject var sync: SyncSession
    @ObservedObject var store: ProjectStore
    @Environment(\.dismiss) private var dismiss

    @State private var scale: Float = 1          // 1 = 1080 canvas baseline
    @State private var fps: Int = 30
    @State private var progress: Double = 0
    @State private var phase: String = "Preparing"
    @State private var running = false
    @State private var doneURL: URL?
    @State private var errorText: String?
    @State private var exporter: KinoExporter?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 18) {
                header
                settingsSection
                if running {
                    progressSection
                } else if let url = doneURL {
                    doneSection(url)
                }
                Spacer()
            }
            .padding(20)
            .background(KinoTheme.backgroundColor)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(KinoTheme.textSecondary)
                }
            }
            .onDisappear {
                exporter?.cancel()
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Export")
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(KinoTheme.textPrimary)
            Text("Renders your edit at full quality. Tip: the preview and the export use the same rendering engine — what you see is what you get.")
                .font(.system(size: 12))
                .foregroundStyle(KinoTheme.textSecondary)
        }
    }

    private var settingsSection: some View {
        VStack(spacing: 0) {
            settingRow(label: "Resolution") {
                Picker("", selection: $scale) {
                    Text("720p").tag(Float(0.67))
                    Text("1080p").tag(Float(1))
                    Text("4K").tag(Float(4 * 1080 / 1080))
                }
                .pickerStyle(.segmented)
            }
            settingRow(label: "Frame rate") {
                Picker("", selection: $fps) {
                    Text("30").tag(30)
                    Text("60").tag(60)
                    Text("24").tag(24)
                }
                .pickerStyle(.segmented)
            }
        }
        .background(KinoTheme.ink1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func settingRow<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack {
            Text(label).font(.system(size: 14)).foregroundStyle(KinoTheme.textPrimary)
            Spacer()
            content()
        }
        .padding(14)
    }

    private var progressSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(phase).font(.system(size: 13, weight: .medium)).foregroundStyle(KinoTheme.textSecondary)
                Spacer()
                Text("\(Int(progress * 100))%").font(.system(size: 13, weight: .semibold)).foregroundStyle(KinoTheme.textPrimary)
            }
            ProgressView(value: progress).tint(KinoTheme.accent)
            Button("Cancel") {
                exporter?.cancel()
            }
            .font(.system(size: 13))
            .foregroundStyle(KinoTheme.danger)
        }
        .padding(16)
        .background(KinoTheme.ink1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func doneSection(_ url: URL) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(KinoTheme.success)
            Text("Render complete").font(.system(size: 16, weight: .semibold)).foregroundStyle(KinoTheme.textPrimary)
            Text(url.lastPathComponent).font(.system(size: 11)).foregroundStyle(KinoTheme.textTertiary)
            HStack(spacing: 12) {
                Button {
                    saveToPhotos(url)
                } label: {
                    Label("Save to Photos", systemImage: "square.and.arrow.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(KinoTheme.accentGradient, in: Capsule())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                ShareLink(item: url) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                        .background(KinoTheme.ink3, in: Capsule())
                        .foregroundStyle(KinoTheme.textPrimary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .background(KinoTheme.ink1, in: RoundedRectangle(cornerRadius: 14))
    }

    private func startExport() {
        guard !running else { return }
        running = true
        progress = 0
        phase = "Building composition"
        let exporter = KinoExporter()
        self.exporter = exporter
        Task {
            do {
                let url = try await exporter.export(
                    project: sync.session.project,
                    scale: scale,
                    fps: Rational(fps: fps) ?? .fps30,
                    onProgress: { p, ph in
                        Task { @MainActor in
                            self.progress = p
                            self.phase = ph
                        }
                    })
                await MainActor.run {
                    doneURL = url
                    running = false
                }
            } catch KinoExporter.ExportError.cancelled {
                await MainActor.run { running = false }
            } catch {
                await MainActor.run {
                    running = false
                    errorText = error.localizedDescription
                }
            }
        }
    }

    private func saveToPhotos(_ url: URL) {
        PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        } completionHandler: { _, err in
            DispatchQueue.main.async {
                if err != nil {
                    errorText = err!.localizedDescription
                } else {
                    errorText = nil
                    phase = "Saved to Photos"
                    KinoHaptics.success()
                }
            }
        }
    }
}

extension Rational {
    init?(fps: Int) {
        self.init(Int64(fps), 1)
    }
}
