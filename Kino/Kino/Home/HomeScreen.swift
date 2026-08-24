import PhotosUI
import SwiftUI
import KinoEngine

struct HomeScreen: View {
    @StateObject private var store = ProjectStore()
    @StateObject private var importer = MediaImporter()
    @State private var path = NavigationPath()
    @State private var showImporter = false
    @State private var importErr: String?
    @State private var showDelete: ProjectStore.ProjectSummary?
    @State private var renaming: ProjectStore.ProjectSummary?
    @State private var renameText = ""
    @State private var pendingImportIdentifiers: [String] = []
    @State private var creatingNew = false

    var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    newProjectCard
                    if store.projects.isEmpty {
                        emptyState
                    } else {
                        section("All Projects") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 14)], spacing: 14) {
                                ForEach(store.projects) { summary in
                                    ProjectCard(summary: summary, onTap: {
                                        open(summary)
                                    }, onMenu: { choice in
                                        handle(summary, action: choice)
                                    })
                                }
                            }
                        }
                    }
                }
                .padding(18)
            }
            .background(KinoTheme.backgroundColor)
            .toolbar(.hidden, for: .navigationBar)
        }
        .sheet(isPresented: $showImporter) {
            KinoMediaPicker { identifiers in
                pendingImportIdentifiers = identifiers
                taskImport()
            }
            .ignoresSafeArea()
        }
        .alert("Import Failed", isPresented: Binding(get: { importErr != nil }, set: { if !$0 { importErr = nil } })) {
            Button("OK") { importErr = nil }
        } message: { Text(importErr ?? "") }
        .confirmationDialog("Project Actions", isPresented: Binding(get: { showDelete != nil }, set: { _ in }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) { deleteProject() }
            Button("Duplicate") { duplicateProject() }
            Button("Rename") { startRename() }
            Button("Cancel", role: .cancel) { showDelete = nil }
        }
        .alert("Rename Project", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Save") { applyRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .onAppear { _ = store.reloadIndex() }
    }

    // MARK: sections

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "clapperboard.fill")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(KinoTheme.accentGradient)
            VStack(alignment: .leading, spacing: 1) {
                Text("Kino").font(.system(size: 22, weight: .bold, design: .rounded)).foregroundStyle(KinoTheme.textPrimary)
                Text("Video Studio").font(.system(size: 12)).foregroundStyle(KinoTheme.textSecondary)
            }
            Spacer()
            if creatingNew {
                ProgressView().tint(KinoTheme.accent)
            }
        }
        .padding(.top, 6)
    }

    private var newProjectCard: some View {
        Button(action: createProject) {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14).fill(KinoTheme.accentGradient)
                    Image(systemName: "plus")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 62, height: 62)
                VStack(alignment: .leading, spacing: 4) {
                    Text("New Project").font(.system(size: 17, weight: .semibold)).foregroundStyle(KinoTheme.textPrimary)
                    Text("Start editing: video, photos, audio, text").font(.system(size: 12)).foregroundStyle(KinoTheme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(KinoTheme.textTertiary)
            }
            .padding(14)
            .background(KinoTheme.ink1, in: RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("new-project-button")
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Image(systemName: "film.stack")
                .font(.system(size: 48))
                .foregroundStyle(KinoTheme.ink4)
            Text("No projects yet")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(KinoTheme.textPrimary)
            Text("Import clips from your library and create your first edit.")
                .font(.system(size: 12))
                .foregroundStyle(KinoTheme.textTertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .kerning(1.1)
                .foregroundStyle(KinoTheme.textTertiary)
            content()
        }
    }

    // MARK: actions

    private func createProject() {
        creatingNew = true
        Task {
            defer { creatingNew = false }
            do {
                let p = try store.createProject(name: defaultProjectName())
                _ = store.reloadIndex()
                path.append(p.meta.id)
            } catch {
                importErr = "Could not create project: \(error.localizedDescription)"
            }
        }
    }

    private func defaultProjectName() -> String {
        let df = DateFormatter()
        df.dateFormat = "MMM d"
        return "Untitled \(store.projects.count + 1)"
    }

    private func open(_ summary: ProjectStore.ProjectSummary) {
        path.append(summary.id)
    }

    private func handle(_ summary: ProjectStore.ProjectSummary, action: ProjectContextAction) {
        switch action {
        case .duplicate:
            _ = try? store.duplicate(summary.id)
            _ = store.reloadIndex()
        case .delete:
            showDelete = summary
        case .rename:
            renaming = summary
            renameText = summary.name
        }
    }

    private func deleteProject() {
        guard let s = showDelete else { return }
        try? store.delete(s.id)
        _ = store.reloadIndex()
        showDelete = nil
    }

    private func duplicateProject() {
        guard let s = showDelete else { return }
        _ = try? store.duplicate(s.id)
        _ = store.reloadIndex()
        showDelete = nil
    }

    private func startRename() {
        guard let s = renaming else { return }
        renameText = s.name
    }

    private func applyRename() {
        guard let s = renaming else { return }
        if var p = store.load(s.id) {
            try? store.rename(&p, renameText)
        }
        renaming = nil
    }

    private func taskImport() {
        guard !pendingImportIdentifiers.isEmpty else { return }
        Task {
            do {
                _ = try await importer.importAssets(identifiers: pendingImportIdentifiers)
            } catch {
                importErr = error.localizedDescription
            }
        }
    }
}

enum ProjectContextAction {
    case duplicate, delete, rename
}

struct ProjectCard: View {
    let summary: ProjectStore.ProjectSummary
    var onTap: () -> Void
    var onMenu: (ProjectContextAction) -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12).fill(KinoTheme.ink3)
                    if let uri = summary.thumbnailURI {
                        ThumbBox(uri: uri)
                    } else {
                        Image(systemName: "film")
                            .font(.system(size: 26))
                            .foregroundStyle(KinoTheme.textTertiary)
                    }
                    VStack {
                        Spacer()
                        HStack {
                            Text(summary.canvas.preset.display)
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.black.opacity(0.55), in: Capsule())
                        }
                        .padding(6)
                    }
                }
                .frame(height: 96)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 2) {
                    Text(summary.name).font(.system(size: 13, weight: .semibold)).foregroundStyle(KinoTheme.textPrimary).lineLimit(1)
                    HStack(spacing: 4) {
                        Text(relative(summary.modifiedAt)).font(.system(size: 11)).foregroundStyle(KinoTheme.textTertiary)
                        Text("·").foregroundStyle(KinoTheme.textTertiary)
                        Text(formatDuration(summary.duration)).font(.system(size: 11)).foregroundStyle(KinoTheme.textTertiary)
                    }
                }
            }
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Rename") { onMenu(.rename) }
            Button("Duplicate") { onMenu(.duplicate) }
            Button("Delete", role: .destructive) { onMenu(.delete) }
        }
    }

    private func relative(_ d: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .short
        return f.localizedString(for: d, relativeTo: Date())
    }

    private func formatDuration(_ d: KTime) -> String {
        String(format: "%d:%02d", Int(d.seconds) / 60, Int(d.seconds) % 60)
    }
}

struct ThumbBox: View {
    let uri: String
    @State private var img: UIImage?
    var body: some View {
        Group {
            if let img {
                Image(uiImage: img).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(KinoTheme.ink3)
            }
        }
        .task {
            ThumbnailService.shared.thumbnail(targetSize: CGSize(width: 200, height: 200), uri: uri, at: KTime(seconds: 2)) { cg in
                if let cg { img = UIImage(cgImage: cg) }
            }
        }
    }
}
