//
//  NoteEditorView.swift
//  MDE
//

import SwiftUI
import UniformTypeIdentifiers

struct NoteEditorView: View {
    let store: VaultStore
    @Bindable var editorState: VaultEditorState
    @Bindable var listState: VaultListState
    let noteID: String?
    @Binding var selectedNoteID: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var editorText = ""
    @State private var loadedNoteID: String?
    @State private var backlinks: [NoteListItem] = []
    @State private var backlinksExpanded = false
    @State private var backlinksLoaded = false
    @State private var errorMessage: String?
    @State private var pendingWikiLinkTitle: String?
    @State private var showCreateWikiLinkSheet = false
    @State private var showExportPicker = false
    @State private var showNotePackageExport = false
    @State private var showNoteZipExport = false
    @State private var showNotePDFExport = false
    @State private var showImageImporter = false
    @State private var exportDocument = MarkdownExportDocument()
    @State private var notePackageExportDocument = VaultFolderExportDocument()
    @State private var noteZipExportDocument = VaultZipExportDocument()
    @State private var notePDFExportDocument = VaultPDFExportDocument()
    @State private var editorSummary: NoteListItem?
    @State private var isTrashedNote = false

    var body: some View {
        Group {
            if let activeNoteID = noteID, let summary = editorSummary {
                editorContent(activeNoteID: activeNoteID, summary: summary)
            } else if noteID != nil {
                ProgressView("Loading note…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "square.and.pencil",
                    description: Text("Choose a note from the list or create a new one.")
                )
                .accessibilityLabel(AccessibilityLabels.emptyNoteSelection)
            }
        }
        .task(id: noteID) {
            guard let id = noteID else {
                editorSummary = nil
                isTrashedNote = false
                return
            }
            resetBacklinksState()
            refreshEditorContext(noteID: id)
            loadNote(id: id)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .fileExporter(
            isPresented: $showExportPicker,
            document: exportDocument,
            contentType: .plainText,
            defaultFilename: noteID.map { store.exportFilename(for: $0) } ?? "Note.md"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showNotePackageExport,
            document: notePackageExportDocument,
            contentType: .folder,
            defaultFilename: noteID.map { store.exportFilename(for: $0).replacingOccurrences(of: ".md", with: "") } ?? "note-export"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showNoteZipExport,
            document: noteZipExportDocument,
            contentType: .zip,
            defaultFilename: noteID.map { store.exportFilename(for: $0).replacingOccurrences(of: ".md", with: ".zip") } ?? "note-export.zip"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .fileExporter(
            isPresented: $showNotePDFExport,
            document: notePDFExportDocument,
            contentType: .pdf,
            defaultFilename: noteID.map { store.exportFilename(for: $0).replacingOccurrences(of: ".md", with: ".pdf") } ?? "note-export.pdf"
        ) { result in
            if case .failure(let error) = result {
                errorMessage = error.localizedDescription
            }
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .confirmationDialog(
            "Create note?",
            isPresented: $showCreateWikiLinkSheet,
            titleVisibility: .visible,
            presenting: pendingWikiLinkTitle
        ) { title in
            Button("Create \"\(title)\"") {
                createWikiLinkTarget(title: title)
            }
            Button("Cancel", role: .cancel) {}
        } message: { title in
            Text("No note titled \"\(title)\" exists yet.")
        }
    }

    @ViewBuilder
    private func editorContent(activeNoteID: String, summary: NoteListItem) -> some View {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.noteDisplayTitle(summary))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

                    if isTrashedNote {
                        HStack(spacing: 8) {
                            Image(systemName: "trash")
                                .foregroundStyle(.secondary)
                            Text("This note is in Trash. Restore it to edit.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Button("Restore") {
                                restoreTrashedNote(id: activeNoteID)
                            }
                            .controlSize(.small)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                        .accessibilityLabel(AccessibilityLabels.trashedNoteReadOnly)
                    }

                    if let autosaveError = editorState.autosaveErrorMessage {
                        HStack(spacing: 8) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                            Text(autosaveError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 4)
                        .accessibilityLabel("Save error: \(autosaveError)")
                    }

                    backlinksSection(noteID: activeNoteID, title: summary.title)

                    PlatformMarkdownEditor(
                        text: $editorText,
                        resolvedLinkTitles: store.resolvedWikiLinkTitles(in: editorText),
                        baseFontSize: EditorTypography.baseFontSize(for: dynamicTypeSize),
                        reduceMotion: reduceMotion,
                        noteTitle: store.noteDisplayTitle(summary),
                        imageURLForPath: { path in store.assetURL(forMarkdownPath: path) },
                        onTextChange: { updated in
                            guard !isTrashedNote else { return }
                            store.scheduleAutosave(noteID: activeNoteID, content: updated)
                        },
                        onWikiLinkClick: { title in
                            handleWikiLinkClick(title)
                        }
                    )
                }
                .accessibilityLabel(AccessibilityLabels.noteEditor)
                #if os(macOS)
                .focusSection()
                #endif
                .toolbar {
                    ToolbarItem {
                        Button {
                            showImageImporter = true
                        } label: {
                            Label("Insert Image", systemImage: "photo")
                        }
                        .disabled(isTrashedNote || !store.isPackageAttached)
                        .accessibilityLabel(AccessibilityLabels.insertImage)
                        .help(store.isPackageAttached ? "Insert image from file" : "Save vault to disk before adding images")
                    }
                    ToolbarItem {
                        Menu {
                            Button {
                                prepareMarkdownExport(noteID: activeNoteID)
                            } label: {
                                Label("Markdown File…", systemImage: "doc.text")
                            }
                            Button {
                                prepareNotePackageExport(noteID: activeNoteID)
                            } label: {
                                Label("Package (Folder)…", systemImage: "folder")
                            }
                            Button {
                                prepareNoteZipExport(noteID: activeNoteID)
                            } label: {
                                Label("Package (Zip)…", systemImage: "doc.zipper")
                            }
                            Button {
                                prepareNotePDFExport(noteID: activeNoteID)
                            } label: {
                                Label("PDF…", systemImage: "doc.richtext")
                            }
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel(AccessibilityLabels.exportNote)
                        .help("Export note as Markdown or package with assets")
                    }
                }
                .fileImporter(
                    isPresented: $showImageImporter,
                    allowedContentTypes: [.image, .png, .jpeg],
                    allowsMultipleSelection: false
                ) { result in
                    importImage(result, noteID: activeNoteID)
                }
                .onChange(of: editorState.contentEpoch) { _, _ in
                    syncEditorFromStore(noteID: activeNoteID)
                }
                .onChange(of: listState.revision) { _, _ in
                    refreshEditorContext(noteID: activeNoteID)
                    if !isTrashedNote, store.noteSummary(id: activeNoteID) == nil {
                        selectedNoteID = nil
                    }
                }
                .onChange(of: editorState.linksRevision) { _, _ in
                    if backlinksExpanded, backlinksLoaded {
                        reloadBacklinks(noteID: activeNoteID, title: summary.title)
                    }
                }
                .onChange(of: backlinksExpanded) { _, expanded in
                    if expanded, !backlinksLoaded {
                        reloadBacklinks(noteID: activeNoteID, title: summary.title)
                        backlinksLoaded = true
                    }
                }
                .onChange(of: editorState.autosaveErrorMessage) { _, message in
                    if let message {
                        errorMessage = message
                    }
                }
                .background(shortcutButtons(noteID: activeNoteID))
    }

    @ViewBuilder
    private func backlinksSection(noteID: String, title: String) -> some View {
        DisclosureGroup(
            isExpanded: $backlinksExpanded,
            content: {
                if backlinks.isEmpty {
                    Text("No notes link here yet")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 8)
                        .accessibilityLabel(AccessibilityLabels.emptyBacklinks)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(backlinks) { backlink in
                                Button {
                                    selectedNoteID = backlink.id
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(store.noteDisplayTitle(backlink))
                                            .font(.caption.weight(.medium))
                                        if !backlink.snippet.isEmpty {
                                            Text(backlink.snippet)
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                                .lineLimit(1)
                                        }
                                    }
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel(
                                    AccessibilityLabels.backlink(title: store.noteDisplayTitle(backlink))
                                )
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                    .padding(.bottom, 8)
                }
            },
            label: {
                Text("Backlinks")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)
            }
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
        .accessibilityLabel(AccessibilityLabels.backlinksPanel)
    }

    @ViewBuilder
    private func shortcutButtons(noteID: String) -> some View {
        Group {
            Button("") { saveNow(noteID: noteID) }
                .keyboardShortcut("s", modifiers: .command)
                .hidden()

            Button("") { selectedNoteID = nil }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()

            Button("") { togglePin(noteID: noteID) }
                .keyboardShortcut("p", modifiers: [.command, .shift])
                .hidden()
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    private func loadNote(id: String) {
        loadedNoteID = id
        if let note = try? store.fetchNote(id: id, includeDeleted: true) {
            editorText = note.content
            isTrashedNote = note.isDeleted
            if !note.isDeleted {
                ColdLaunchBenchmark.markEditorReady()
            }
        }
    }

    private func refreshEditorContext(noteID: String) {
        editorSummary = try? store.fetchListItem(id: noteID)
        if let note = try? store.fetchNote(id: noteID, includeDeleted: true) {
            isTrashedNote = note.isDeleted
        }
    }

    private func restoreTrashedNote(id: String) {
        do {
            try store.restoreNote(id: id)
            try store.flushPackageIfNeeded()
            refreshEditorContext(noteID: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetBacklinksState() {
        backlinks = []
        backlinksExpanded = false
        backlinksLoaded = false
    }

    private func syncEditorFromStore(noteID: String) {
        guard noteID == loadedNoteID,
              let note = try? store.fetchNote(id: noteID, includeDeleted: true),
              editorText != note.content else { return }
        editorText = note.content
        isTrashedNote = note.isDeleted
    }

    private func reloadBacklinks(noteID: String, title: String) {
        do {
            backlinks = try store.fetchBacklinkSummaries(for: noteID, title: title)
        } catch {
            backlinks = []
        }
    }

    private func prepareMarkdownExport(noteID: String) {
        do {
            let markdown = try store.exportNoteAsMarkdown(id: noteID)
            exportDocument = MarkdownExportDocument(text: markdown)
            showExportPicker = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareNotePackageExport(noteID: String) {
        do {
            let wrapper = try store.makeNotePackageExportWrapper(noteID: noteID)
            notePackageExportDocument = VaultFolderExportDocument(wrapper: wrapper)
            showNotePackageExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareNoteZipExport(noteID: String) {
        do {
            let data = try store.makeNoteZipExportData(noteID: noteID)
            noteZipExportDocument = VaultZipExportDocument(data: data)
            showNoteZipExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func prepareNotePDFExport(noteID: String) {
        do {
            let data = try store.makeNotePDFExportData(noteID: noteID)
            notePDFExportDocument = VaultPDFExportDocument(data: data)
            showNotePDFExport = true
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func importImage(_ result: Result<[URL], Error>, noteID: String) {
        guard case .success(let urls) = result, let url = urls.first else { return }
        do {
            let alt = url.deletingPathExtension().lastPathComponent
            let markdown = try store.importImage(from: url, intoNoteID: noteID, altText: alt)
            let separator: String
            if editorText.isEmpty {
                separator = ""
            } else if editorText.hasSuffix("\n\n") {
                separator = ""
            } else if editorText.hasSuffix("\n") {
                separator = "\n"
            } else {
                separator = "\n\n"
            }
            editorText += separator + markdown
            store.scheduleAutosave(noteID: noteID, content: editorText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func saveNow(noteID: String) {
        do {
            try store.saveNow(noteID: noteID, content: editorText)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePin(noteID: String) {
        do {
            try store.togglePin(id: noteID)
            try store.flushPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func handleWikiLinkClick(_ title: String) {
        if let targetID = store.noteID(forTitle: title) {
            selectedNoteID = targetID
        } else {
            pendingWikiLinkTitle = title
            showCreateWikiLinkSheet = true
        }
    }

    private func createWikiLinkTarget(title: String) {
        do {
            let note: Note
            if DailyNoteHelper.isDailyNoteTitle(title) {
                let date = DailyNoteHelper.parseDate(from: title) ?? Date()
                note = try store.openDailyNote(for: date)
            } else {
                note = try store.createNote(title: title)
            }
            try store.flushPackageIfNeeded()
            selectedNoteID = note.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
