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

    @State private var displayedNotes: [NoteListItem] = []
    @State private var searchResults: [SearchResult] = []
    @State private var errorMessage: String?
    @State private var mergePrimaryNote: NoteListItem?
    @State private var searchTask: Task<Void, Never>?

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
                        NoteRowView(item: note, store: store)
                            .tag(note.id)
                            .contextMenu {
                                noteContextMenu(for: note)
                            }
                    }
                    .onDelete(perform: deleteNotes)
                }
            }
        }
        .searchable(text: $searchQuery, prompt: "Search notes")
        .navigationTitle("Notes")
        .accessibilityLabel(AccessibilityLabels.noteList)
        .accessibilityIdentifier("note-list")
        #if os(macOS)
        .focusSection()
        #endif
        .toolbar {
            ToolbarItem {
                Button(action: addNote) {
                    Label("New Note", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .accessibilityLabel("New note")
                .help("Create a new note")
            }
        }
        .onAppear(perform: reload)
        .onChange(of: tagPath) { _, _ in reload() }
        .onChange(of: store.listRevision) { _, _ in reload() }
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .alert("Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .sheet(item: $mergePrimaryNote) { primary in
            MergeNotesSheet(
                store: store,
                primaryID: primary.id,
                candidates: displayedNotes.filter { $0.id != primary.id },
                onMerge: { otherIDs in
                    performMerge(primaryID: primary.id, otherIDs: otherIDs)
                    mergePrimaryNote = nil
                },
                onCancel: {
                    mergePrimaryNote = nil
                }
            )
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
                    .accessibilityLabel(
                        AccessibilityLabels.searchResult(
                            title: result.title.isEmpty ? "Untitled" : result.title,
                            snippet: result.snippet
                        )
                    )
                }
            }
        }
    }

    @ViewBuilder
    private func noteContextMenu(for note: NoteListItem) -> some View {
        Button(note.isPinned ? "Unpin" : "Pin") {
            togglePin(note)
        }

        Button("Merge…") {
            mergePrimaryNote = note
        }

        Divider()

        Button("Delete", role: .destructive) {
            deleteNote(note)
        }
    }

    private func reload() {
        do {
            displayedNotes = try store.noteSummariesFiltered(by: tagPath)
            if let selectedNoteID, !displayedNotes.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = displayedNotes.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func scheduleSearch(query: String) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            searchResults = []
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(200))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                performSearch(query: trimmed)
            }
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
            try store.flushPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        let legacyNotes = displayedNotes.map {
            Note(id: $0.id, title: $0.title, content: "", updatedAt: $0.updatedAt, isPinned: $0.isPinned)
        }
        do {
            try store.softDeleteNotes(at: offsets, in: legacyNotes)
            try store.flushPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNote(_ note: NoteListItem) {
        do {
            try store.softDeleteNote(id: note.id)
            try store.flushPackageIfNeeded()
            if selectedNoteID == note.id {
                selectedNoteID = displayedNotes.first(where: { $0.id != note.id })?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func togglePin(_ note: NoteListItem) {
        do {
            try store.togglePin(id: note.id)
            try store.flushPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func performMerge(primaryID: String, otherIDs: [String]) {
        do {
            let merged = try store.mergeNotes(primaryID: primaryID, otherIDs: otherIDs)
            try store.flushPackageIfNeeded()
            selectedNoteID = merged.id
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NoteRowView: View {
    let item: NoteListItem
    let store: VaultStore

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if item.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(store.noteDisplayTitle(item))
                    .font(.headline)
                    .lineLimit(1)
                if !store.noteSnippet(item).isEmpty {
                    Text(store.noteSnippet(item))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(item.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AccessibilityLabels.noteRow(
                title: store.noteDisplayTitle(item),
                snippet: store.noteSnippet(item),
                isPinned: item.isPinned,
                updatedAt: item.updatedAt
            )
        )
        .accessibilityAddTraits(item.isPinned ? [.isSelected] : [])
    }
}

private struct MergeNotesSheet: View {
    let store: VaultStore
    let primaryID: String
    let candidates: [NoteListItem]
    let onMerge: ([String]) -> Void
    let onCancel: () -> Void

    @State private var selectedIDs = Set<String>()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Merge into Primary Note")
                .font(.headline)

            if let primary = store.noteSummary(id: primaryID) {
                Text("Primary: \(store.noteDisplayTitle(primary))")
                    .foregroundStyle(.secondary)
            }

            Text("Select notes to merge:")
                .font(.subheadline)

            ForEach(candidates) { note in
                Toggle(isOn: Binding(
                    get: { selectedIDs.contains(note.id) },
                    set: { isOn in
                        if isOn {
                            selectedIDs.insert(note.id)
                        } else {
                            selectedIDs.remove(note.id)
                        }
                    }
                )) {
                    Text(store.noteDisplayTitle(note))
                }
            }
            .frame(minHeight: 160)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel)
                Button("Merge") {
                    onMerge(Array(selectedIDs))
                }
                .disabled(selectedIDs.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 360, height: 360)
    }
}
