//
//  NoteEditorView.swift
//  MDE
//

import SwiftUI

struct NoteEditorView: View {
    @Bindable var store: VaultStore
    let noteID: String?
    @Binding var selectedNoteID: String?

    @State private var editorText = ""
    @State private var loadedNoteID: String?
    @State private var backlinks: [Note] = []
    @State private var errorMessage: String?
    @State private var pendingWikiLinkTitle: String?
    @State private var showCreateWikiLinkSheet = false

    var body: some View {
        Group {
            if let noteID, let note = store.notes.first(where: { $0.id == noteID }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.noteDisplayTitle(note))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    if !backlinks.isEmpty {
                        backlinksPanel
                    }

                    MarkdownTextView(
                        text: $editorText,
                        resolvedLinkTitles: store.resolvedWikiLinkTitles(in: editorText),
                        onTextChange: { updated in
                            store.scheduleAutosave(noteID: noteID, content: updated)
                        },
                        onWikiLinkClick: { title in
                            handleWikiLinkClick(title)
                        }
                    )
                }
                .onAppear {
                    load(note: note)
                    reloadBacklinks(for: note)
                }
                .onChange(of: noteID) { _, _ in
                    if let note = store.notes.first(where: { $0.id == noteID }) {
                        load(note: note)
                        reloadBacklinks(for: note)
                    }
                }
                .onChange(of: note.content) { _, newValue in
                    if noteID == loadedNoteID, editorText != newValue {
                        editorText = newValue
                    }
                }
                .onChange(of: store.notes) { _, _ in
                    if let note = store.notes.first(where: { $0.id == noteID }) {
                        reloadBacklinks(for: note)
                    }
                }
            } else {
                ContentUnavailableView(
                    "Select a note",
                    systemImage: "square.and.pencil",
                    description: Text("Choose a note from the list or create a new one.")
                )
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

    private var backlinksPanel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Backlinks")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(backlinks) { backlink in
                        Button(store.noteDisplayTitle(backlink)) {
                            selectedNoteID = backlink.id
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
                .padding(.horizontal, 16)
            }
            .padding(.bottom, 8)
        }
    }

    private func load(note: Note) {
        loadedNoteID = note.id
        editorText = note.content
    }

    private func reloadBacklinks(for note: Note) {
        do {
            backlinks = try store.fetchBacklinks(for: note.id, title: note.title)
        } catch {
            backlinks = []
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
            try store.persistToPackageIfNeeded()
            selectedNoteID = note.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
