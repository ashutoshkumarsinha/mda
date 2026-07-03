//
//  NoteEditorView.swift
//  MDE
//

import SwiftUI

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
    @State private var errorMessage: String?
    @State private var pendingWikiLinkTitle: String?
    @State private var showCreateWikiLinkSheet = false

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

                    if !backlinks.isEmpty {
                        backlinksPanel
                    }

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
                .onAppear {
                    loadNote(id: activeNoteID)
                    reloadBacklinks(noteID: activeNoteID, title: summary.title)
                }
                .onChange(of: noteID) { _, newID in
                    guard let newID else { return }
                    loadNote(id: newID)
                    if let summary = store.noteSummary(id: newID) {
                        reloadBacklinks(noteID: newID, title: summary.title)
                    }
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
                    if let summary = store.noteSummary(id: activeNoteID) {
                        reloadBacklinks(noteID: activeNoteID, title: summary.title)
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

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backlinks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(backlinks) { backlink in
                        Button(store.noteDisplayTitle(backlink)) {
                            selectedNoteID = backlink.id
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .accessibilityLabel(AccessibilityLabels.backlink(title: store.noteDisplayTitle(backlink)))
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
        .accessibilityElement(children: .contain)
    }

    private func loadNote(id: String) {
        loadedNoteID = id
        if let note = try? store.fetchNote(id: id) {
            editorText = note.content
        }
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
