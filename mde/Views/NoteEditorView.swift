//
//  NoteEditorView.swift
//  MDE
//

import SwiftUI

struct NoteEditorView: View {
    @Bindable var store: VaultStore
    let noteID: String?

    @State private var editorText = ""
    @State private var loadedNoteID: String?
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if let noteID, let note = store.notes.first(where: { $0.id == noteID }) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(store.noteDisplayTitle(note))
                        .font(.title3.weight(.semibold))
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)

                    MarkdownTextView(text: $editorText) { updated in
                        store.scheduleAutosave(noteID: noteID, content: updated)
                    }
                }
                .onAppear { load(note: note) }
                .onChange(of: noteID) { _, _ in
                    if let note = store.notes.first(where: { $0.id == noteID }) {
                        load(note: note)
                    }
                }
                .onChange(of: note.content) { _, newValue in
                    if noteID == loadedNoteID, editorText != newValue {
                        editorText = newValue
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
    }

    private func load(note: Note) {
        loadedNoteID = note.id
        editorText = note.content
    }
}
