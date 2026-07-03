//
//  NoteListView.swift
//  MDE
//

import SwiftUI

struct NoteListView: View {
    @Bindable var store: VaultStore
    @Binding var selectedNoteID: String?
    @Binding var searchQuery: String
    let tagPath: String?

    @State private var displayedNotes: [Note] = []
    @State private var searchResults: [SearchResult] = []
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isSearching {
                searchResultsList
            } else if displayedNotes.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "note.text",
                    description: Text(emptyDescription)
                )
            } else {
                List(selection: $selectedNoteID) {
                    ForEach(displayedNotes) { note in
                        NoteRowView(note: note, store: store)
                            .tag(note.id)
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .searchable(text: $searchQuery, prompt: "Search notes")
        .navigationTitle("Notes")
        .toolbar {
            ToolbarItem {
                Button(action: addNote) {
                    Label("New Note", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
            }
        }
        .onAppear(perform: reload)
        .onChange(of: tagPath) { _, _ in reload() }
        .onChange(of: store.notes) { _, _ in reload() }
        .onChange(of: searchQuery) { _, newValue in
            performSearch(query: newValue)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var emptyTitle: String {
        if tagPath != nil { return "No notes match this tag" }
        return "No notes yet"
    }

    private var emptyDescription: String {
        if tagPath != nil { return "Try another tag or create a note with this tag inline." }
        return "Create your first note to get started."
    }

    @ViewBuilder
    private var searchResultsList: some View {
        if searchResults.isEmpty {
            ContentUnavailableView.search(text: searchQuery)
        } else {
            List(selection: $selectedNoteID) {
                ForEach(searchResults) { result in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(result.title.isEmpty ? "Untitled" : result.title)
                            .font(.headline)
                        if !result.snippet.isEmpty {
                            Text(result.snippet)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }
                    }
                    .tag(result.id)
                }
            }
        }
    }

    private func reload() {
        do {
            displayedNotes = try store.notesFiltered(by: tagPath)
            if let selectedNoteID, !displayedNotes.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = displayedNotes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performSearch(query: String) {
        do {
            searchResults = try store.searchNotes(query: query)
            if let first = searchResults.first {
                selectedNoteID = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func addNote() {
        do {
            let note = try store.createNote()
            selectedNoteID = note.id
            try store.persistToPackageIfNeeded()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        do {
            try store.softDeleteNotes(at: offsets, in: displayedNotes)
            try store.persistToPackageIfNeeded()
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NoteRowView: View {
    let note: Note
    let store: VaultStore

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(store.noteDisplayTitle(note))
                .font(.headline)
                .lineLimit(1)
            if !store.noteSnippet(note).isEmpty {
                Text(store.noteSnippet(note))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(note.updatedAt, format: .relative(presentation: .named))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}
