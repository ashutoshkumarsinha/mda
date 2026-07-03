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
    @State private var exportDocument = MarkdownExportDocument()

    var body: some View {
        Group {
            if let activeNoteID = noteID, let summary = store.noteSummary(id: activeNoteID) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.noteDisplayTitle(summary))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                        .accessibilityAddTraits(.isHeader)

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
                        onTextChange: { updated in
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
                            prepareExport(noteID: activeNoteID)
                        } label: {
                            Label("Export", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityLabel(AccessibilityLabels.exportNote)
                        .help("Export note as Markdown")
                    }
                }
                .onAppear {
                    loadNote(id: activeNoteID)
                }
                .onChange(of: noteID) { _, newID in
                    guard let newID else { return }
                    resetBacklinksState()
                    loadNote(id: newID)
                }
                .onChange(of: editorState.contentEpoch) { _, _ in
                    syncEditorFromStore(noteID: activeNoteID)
                }
                .onChange(of: listState.revision) { _, _ in
                    if store.noteSummary(id: activeNoteID) == nil {
                        selectedNoteID = nil
                    }
                }
                .onChange(of: editorState.linksRevision) { _, _ in
                    if backlinksExpanded, backlinksLoaded,
                       let summary = store.noteSummary(id: activeNoteID) {
                        reloadBacklinks(noteID: activeNoteID, title: summary.title)
                    }
                }
                .onChange(of: backlinksExpanded) { _, expanded in
                    if expanded, !backlinksLoaded,
                       let summary = store.noteSummary(id: activeNoteID) {
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
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "square.and.pencil",
                    description: Text("Choose a note from the list or create a new one.")
                )
                .accessibilityLabel(AccessibilityLabels.emptyNoteSelection)
            }
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
                                Button(store.noteDisplayTitle(backlink)) {
                                    selectedNoteID = backlink.id
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
        if let note = try? store.fetchNote(id: id) {
            editorText = note.content
        }
    }

    private func resetBacklinksState() {
        backlinks = []
        backlinksExpanded = false
        backlinksLoaded = false
    }

    private func syncEditorFromStore(noteID: String) {
        guard noteID == loadedNoteID,
              let note = try? store.fetchNote(id: noteID),
              editorText != note.content else { return }
        editorText = note.content
    }

    private func reloadBacklinks(noteID: String, title: String) {
        do {
            backlinks = try store.fetchBacklinkSummaries(for: noteID, title: title)
        } catch {
            backlinks = []
        }
    }

    private func prepareExport(noteID: String) {
        do {
            let markdown = try store.exportNoteAsMarkdown(id: noteID)
            exportDocument = MarkdownExportDocument(text: markdown)
            showExportPicker = true
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
            let note = try store.createNote(title: title)
            try store.flushPackageIfNeeded()
            selectedNoteID = note.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
