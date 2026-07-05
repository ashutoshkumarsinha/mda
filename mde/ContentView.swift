//
//  ContentView.swift
//  MDE
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var store: VaultStore
    /// When false, sync bootstrap waits until the vault package is attached on disk.
    var isPackageBound: Bool = true

    @State private var selectedTagPath: String?
    @State private var selectedNoteID: String?
    @State private var searchQuery = ""
    @State private var showOnboarding = ContentView.shouldShowOnboarding
    @State private var showSyncSetup = false
    @State private var syncCoordinator: SyncCoordinator?
    @State private var showRecoveryAlert = false
    @State private var recoveryError: String?
    @State private var showGraph = false
    @State private var showVaultExport = false
    @State private var vaultExportDocument = MarkdownExportDocument()
    @State private var showVaultFolderExport = false
    @State private var vaultFolderExportDocument = VaultFolderExportDocument()
    @State private var showVaultZipExport = false
    @State private var vaultZipExportDocument = VaultZipExportDocument()
    @State private var showMarkdownImport = false
    @State private var showNotionImport = false
    @State private var importError: String?
    @State private var importBannerMessage: String?
    @State private var pendingPackageImport: PendingPackageImport?
    @State private var showPackageImportSheet = false

    private struct PendingPackageImport {
        var url: URL
        var isZip: Bool
    }

    #if DEBUG
    @State private var showDeveloperSettings = false
    #endif

    #if os(macOS)
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    #endif

    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var compactScreen: CompactScreen = .notes
    #endif

    var body: some View {
        VStack(spacing: 0) {
            if let conflict = syncCoordinator?.conflict {
                SyncConflictBanner(
                    conflict: conflict,
                    onKeepLocal: {
                        Task { await syncCoordinator?.resolveConflict(keepLocal: true) }
                    },
                    onKeepCloud: {
                        Task { await syncCoordinator?.resolveConflict(keepLocal: false) }
                    }
                )
            }

            if let importBannerMessage {
                ImportBanner(message: importBannerMessage) {
                    self.importBannerMessage = nil
                }
            }

            #if os(iOS)
            if horizontalSizeClass == .regular {
                splitLayout
            } else {
                compactLayout
            }
            #else
            splitLayout
            #endif
        }
        .toolbar {
            if let syncCoordinator {
                ToolbarItem(placement: .automatic) {
                    SyncStatusToolbarContent(
                        coordinator: syncCoordinator,
                        showSetup: $showSyncSetup
                    )
                }
            }
            #if DEBUG
            ToolbarItem(placement: .automatic) {
                Button {
                    showDeveloperSettings = true
                } label: {
                    Label("Developer", systemImage: "gauge.with.dots.needle.67percent")
                }
                .help("Performance signposts and memory gauge")
            }
            #endif
            ToolbarItem(placement: .automatic) {
                Menu {
                    Button {
                        showGraph = true
                    } label: {
                        Label("Link Graph", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    Button {
                        prepareVaultExport()
                    } label: {
                        Label("Export Vault (Single File)…", systemImage: "doc.text")
                    }
                    Button {
                        prepareVaultFolderExport()
                    } label: {
                        Label("Export Vault (Package)…", systemImage: "square.and.arrow.up.on.square")
                    }
                    Button {
                        prepareVaultZipExport()
                    } label: {
                        Label("Export Vault (Zip)…", systemImage: "doc.zipper")
                    }
                    Button {
                        showNotionImport = true
                    } label: {
                        Label("Import Notion Export…", systemImage: "square.and.arrow.down.on.square")
                    }
                    Button {
                        showMarkdownImport = true
                    } label: {
                        Label("Import Markdown / Package…", systemImage: "square.and.arrow.down")
                    }
                } label: {
                    Label("Vault", systemImage: "archivebox")
                }
                .accessibilityLabel(AccessibilityLabels.vaultMenu)
            }
        }
        .sheet(isPresented: $showGraph) {
            WikiLinkGraphView(store: store, selectedNoteID: $selectedNoteID)
                #if os(macOS)
                .frame(minWidth: 640, minHeight: 520)
                #endif
        }
        .fileExporter(
            isPresented: $showVaultExport,
            document: vaultExportDocument,
            contentType: .plainText,
            defaultFilename: "vault-export.md"
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showVaultFolderExport,
            document: vaultFolderExportDocument,
            contentType: .folder,
            defaultFilename: "vault-export"
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showVaultZipExport,
            document: vaultZipExportDocument,
            contentType: .zip,
            defaultFilename: "vault-export.zip"
        ) { result in
            if case .failure(let error) = result {
                importError = error.localizedDescription
            }
        }
        .fileImporter(
            isPresented: $showMarkdownImport,
            allowedContentTypes: [.plainText, .zip, .folder],
            allowsMultipleSelection: true
        ) { result in
            importMarkdownFiles(result)
        }
        .fileImporter(
            isPresented: $showNotionImport,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false
        ) { result in
            importNotionFolder(result)
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView(isPresented: $showOnboarding)
        }
        .sheet(isPresented: $showSyncSetup) {
            if let syncCoordinator {
                SyncSetupView(coordinator: syncCoordinator, isPresented: $showSyncSetup)
            }
        }
        #if DEBUG
        .sheet(isPresented: $showDeveloperSettings) {
            DeveloperSettingsView()
        }
        #endif
        .alert("Database Recovery", isPresented: $showRecoveryAlert) {
            if store.recoveryBackupAvailable {
                Button("Restore Migration Backup") {
                    restoreDatabase(from: .migrationBackup)
                }
            }
            if store.recoveryAutosaveAvailable {
                Button("Restore Last Autosave") {
                    restoreDatabase(from: .autosaveSnapshot)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(recoveryMessage)
        }
        .alert("Recovery Failed", isPresented: Binding(
            get: { recoveryError != nil },
            set: { if !$0 { recoveryError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryError ?? "")
        }
        .alert("Import Error", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(importError ?? "")
        }
        .sheet(isPresented: $showPackageImportSheet) {
            if let pending = pendingPackageImport {
                PackageImportSheet(
                    sourceDescription: pending.isZip
                        ? pending.url.lastPathComponent
                        : pending.url.lastPathComponent,
                    onImport: { mode in
                        performPackageImport(pending: pending, mode: mode)
                    },
                    onCancel: {
                        pendingPackageImport = nil
                        showPackageImportSheet = false
                    }
                )
            }
        }
        .onChange(of: store.needsDatabaseRecovery) { _, needs in
            showRecoveryAlert = needs
        }
        .onAppear {
            showRecoveryAlert = store.needsDatabaseRecovery
        }
        .vaultPackageLifecycle(store: store)
        .background {
            if let syncCoordinator {
                Color.clear
                    .frame(width: 0, height: 0)
                    .syncLifecycle(coordinator: syncCoordinator, networkMonitor: SyncNetworkMonitor())
            }
        }
        .task(id: isPackageBound) {
            guard isPackageBound, syncCoordinator == nil else { return }
            let coordinator = SyncCoordinator(store: store)
            syncCoordinator = coordinator
            await coordinator.bootstrap()
        }
    }

    private var splitLayout: some View {
        #if os(macOS)
        NavigationSplitView(columnVisibility: $splitVisibility) {
            TagSidebarView(listState: store.listState, selectedTagPath: $selectedTagPath)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            NoteListView(
                store: store,
                listState: store.listState,
                selectedNoteID: $selectedNoteID,
                searchQuery: $searchQuery,
                tagPath: selectedTagPath
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        #else
        NavigationSplitView {
            TagSidebarView(listState: store.listState, selectedTagPath: $selectedTagPath)
                .navigationSplitViewColumnWidth(min: 160, ideal: 180, max: 220)
        } content: {
            NoteListView(
                store: store,
                listState: store.listState,
                selectedNoteID: $selectedNoteID,
                searchQuery: $searchQuery,
                tagPath: selectedTagPath
            )
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 320)
        } detail: {
            detailColumn
        }
        .navigationSplitViewStyle(.balanced)
        #endif
    }

    @ViewBuilder
    private var detailColumn: some View {
        if selectedNoteID != nil {
            NoteEditorView(
                store: store,
                editorState: store.editorState,
                listState: store.listState,
                noteID: selectedNoteID,
                selectedNoteID: $selectedNoteID
            )
        } else {
            ContentUnavailableView(
                "Select a note",
                systemImage: "square.and.pencil",
                description: Text("Choose a note from the list or create a new one.")
            )
            .accessibilityLabel(AccessibilityLabels.emptyNoteSelection)
        }
    }

    #if os(iOS)
    private var compactLayout: some View {
        NavigationStack {
            ZStack {
                tagsCompactLayer
                    .opacity(compactScreen == .tags ? 1 : 0)
                    .allowsHitTesting(compactScreen == .tags)
                    .accessibilityHidden(compactScreen != .tags)

                notesCompactLayer
                    .opacity(compactScreen == .notes ? 1 : 0)
                    .allowsHitTesting(compactScreen == .notes)
                    .accessibilityHidden(compactScreen != .notes)

                editorCompactLayer
                    .opacity(compactScreen == .editor ? 1 : 0)
                    .allowsHitTesting(compactScreen == .editor)
                    .accessibilityHidden(compactScreen != .editor)
            }
            .navigationTitle(compactNavigationTitle)
        }
        .onChange(of: selectedNoteID) { _, newID in
            if newID != nil, compactScreen == .notes {
                compactScreen = .editor
            }
            if newID == nil, compactScreen == .editor {
                compactScreen = .notes
            }
        }
    }

    private var tagsCompactLayer: some View {
        TagSidebarView(listState: store.listState, selectedTagPath: $selectedTagPath)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Notes") {
                        compactScreen = .notes
                    }
                }
            }
    }

    private var notesCompactLayer: some View {
        NoteListView(
            store: store,
            listState: store.listState,
            selectedNoteID: $selectedNoteID,
            searchQuery: $searchQuery,
            tagPath: selectedTagPath
        )
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Tags") {
                    compactScreen = .tags
                }
            }
        }
    }

    @ViewBuilder
    private var editorCompactLayer: some View {
        if let selectedNoteID {
            NoteEditorView(
                store: store,
                editorState: store.editorState,
                listState: store.listState,
                noteID: selectedNoteID,
                selectedNoteID: $selectedNoteID
            )
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Back") {
                        compactScreen = .notes
                    }
                }
            }
        }
    }

    private var compactNavigationTitle: String {
        switch compactScreen {
        case .tags: return "Tags"
        case .notes: return "Notes"
        case .editor: return "Editor"
        }
    }

    private enum CompactScreen {
        case tags
        case notes
        case editor
    }
    #endif

    private var recoveryMessage: String {
        switch (store.recoveryBackupAvailable, store.recoveryAutosaveAvailable) {
        case (true, true):
            return "The vault database may be damaged. Restore from the migration backup or the last autosave snapshot."
        case (true, false):
            return "The vault database may be damaged. Restore from the migration backup."
        case (false, true):
            return "The vault database may be damaged. Restore from the last autosave snapshot."
        case (false, false):
            return "The vault database may be damaged and no recovery copy is available."
        }
    }

    private func restoreDatabase(from source: VaultStore.DatabaseRecoverySource) {
        do {
            try store.restoreDatabase(from: source)
        } catch {
            recoveryError = error.localizedDescription
        }
    }

    static var shouldShowOnboarding: Bool {
        if LaunchArguments.skipOnboarding || LaunchArguments.benchmarkColdLaunch {
            return false
        }
        return !UserDefaults.standard.bool(forKey: OnboardingKeys.hasSeenOnboarding)
    }

    private func prepareVaultExport() {
        do {
            let markdown = try store.exportVaultAsCombinedMarkdown()
            vaultExportDocument = MarkdownExportDocument(text: markdown)
            showVaultExport = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func prepareVaultFolderExport() {
        do {
            let wrapper = try store.makeVaultPackageExportWrapper()
            vaultFolderExportDocument = VaultFolderExportDocument(wrapper: wrapper)
            showVaultFolderExport = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func prepareVaultZipExport() {
        do {
            let data = try store.makeVaultZipExportData()
            vaultZipExportDocument = VaultZipExportDocument(data: data)
            showVaultZipExport = true
        } catch {
            importError = error.localizedDescription
        }
    }

    private func importNotionFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            guard let url = urls.first else { return }
            do {
                let accessed = url.startAccessingSecurityScopedResource()
                defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                _ = try store.importNotionDirectory(from: url)
                try store.flushPackageIfNeeded()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func importMarkdownFiles(_ result: Result<[URL], Error>) {
        switch result {
        case .failure(let error):
            importError = error.localizedDescription
        case .success(let urls):
            do {
                for url in urls {
                    let accessed = url.startAccessingSecurityScopedResource()
                    defer { if accessed { url.stopAccessingSecurityScopedResource() } }
                    if url.pathExtension.lowercased() == "zip" {
                        pendingPackageImport = PendingPackageImport(url: url, isZip: true)
                        showPackageImportSheet = true
                        return
                    }
                    if url.hasDirectoryPath {
                        var isDirectory: ObjCBool = false
                        if FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                           isDirectory.boolValue {
                            if VaultPackageImporter.isExportPackage(at: url) {
                                pendingPackageImport = PendingPackageImport(url: url, isZip: false)
                                showPackageImportSheet = true
                                return
                            } else {
                                _ = try store.importObsidianDirectory(from: url)
                            }
                        } else {
                            _ = try store.importMarkdownDirectory(from: url)
                        }
                    } else {
                        _ = try store.importMarkdownFile(from: url)
                    }
                }
                try store.flushPackageIfNeeded()
            } catch {
                importError = error.localizedDescription
            }
        }
    }

    private func performPackageImport(pending: PendingPackageImport, mode: VaultPackageImportMode) {
        do {
            let accessed = pending.url.startAccessingSecurityScopedResource()
            defer { if accessed { pending.url.stopAccessingSecurityScopedResource() } }
            let result: VaultPackageImportResult
            if pending.isZip {
                result = try store.importExportZip(from: pending.url, mode: mode)
            } else {
                result = try store.importExportPackage(from: pending.url, mode: mode)
            }
            if result.assetsSkipped {
                importBannerMessage = "Images were not imported. Save the vault to a package on disk to include assets."
            }
            pendingPackageImport = nil
            showPackageImportSheet = false
            try store.flushPackageIfNeeded()
        } catch {
            importError = error.localizedDescription
            pendingPackageImport = nil
            showPackageImportSheet = false
        }
    }
}

private struct ImportBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Dismiss", action: onDismiss)
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.orange.opacity(0.12))
    }
}

#Preview {
    ContentView(store: VaultStore())
}
