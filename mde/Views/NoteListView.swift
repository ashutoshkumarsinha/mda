//
//  NoteListView.swift
//  MDE
//

import SwiftUI

struct NoteListView: View {
    let store: VaultStore
    @Bindable var listState: VaultListState
    @Binding var selectedNoteID: String?
    @Binding var searchQuery: String
    let tagPath: String?

    @State private var displayedRows: [NoteListRow] = []
    @State private var totalNoteCount = 0
    @State private var loadedNoteCount = VaultStore.listPageSize
    @State private var isLoadingMore = false
    @State private var searchResults: [SearchResult] = []
    @State private var errorMessage: String?
    @State private var mergePrimaryNote: NoteListItem?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        Group {
            if isSearching {
                searchResultsList
            } else if displayedRows.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "note.text",
                    description: Text(emptyDescription)
                )
            } else {
                List(selection: $selectedNoteID) {
                    ForEach(displayedRows) { row in
                        NoteRowView(row: row)
                            .equatable()
                            .id(row.rowIdentity)
                            .tag(row.id)
                            .contextMenu {
                                if let note = store.noteSummary(id: row.id) {
                                    noteContextMenu(for: note)
                                }
                            }
                            .onAppear {
                                if let note = store.noteSummary(id: row.id) {
                                    loadMoreIfNeeded(after: note)
                                }
                            }
                    }
                    .onDelete(perform: deleteNotes)

                    if hasMoreNotes {
                        HStack {
                            Spacer()
                            if isLoadingMore {
                                ProgressView()
                            } else {
                                Text("Scroll for more notes")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                        .listRowSeparator(.hidden)
                    }
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
        .onAppear { reload(resetLoadedWindow: true) }
        .onChange(of: tagPath) { _, _ in reload(resetLoadedWindow: true) }
        .onChange(of: listState.revision) { _, _ in reload(resetLoadedWindow: false) }
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
                candidates: displayedRows.compactMap { store.noteSummary(id: $0.id) }.filter { $0.id != primary.id },
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

    private var hasMoreNotes: Bool {
        displayedRows.count < totalNoteCount
    }

    private func reload(resetLoadedWindow: Bool = false) {
        do {
            if resetLoadedWindow {
                loadedNoteCount = VaultStore.listPageSize
            }
            let limit = max(loadedNoteCount, VaultStore.listPageSize)
            let page = try store.noteSummariesPage(offset: 0, limit: limit, tagPath: tagPath)
            displayedRows = page.map { NoteListRow(item: $0, store: store) }
            totalNoteCount = try store.noteCountFiltered(by: tagPath)
            loadedNoteCount = displayedRows.count
            if let selectedNoteID, !displayedRows.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = displayedRows.first?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded(after note: NoteListItem) {
        guard note.id == displayedRows.last?.id, hasMoreNotes, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try store.noteSummariesPage(
                offset: displayedRows.count,
                limit: VaultStore.listPageSize,
                tagPath: tagPath
            )
            displayedRows.append(contentsOf: next.map { NoteListRow(item: $0, store: store) })
            loadedNoteCount = displayedRows.count
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
        let legacyNotes = displayedRows.map {
            Note(id: $0.id, title: $0.displayTitle, content: "", updatedAt: $0.updatedAt, isPinned: $0.isPinned)
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
                selectedNoteID = displayedRows.first(where: { $0.id != note.id })?.id
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

private struct NoteRowView: View, Equatable {
    let row: NoteListRow

    static func == (lhs: NoteRowView, rhs: NoteRowView) -> Bool {
        lhs.row == rhs.row
    }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            if row.isPinned {
                Image(systemName: "pin.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.top, 3)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text(row.displayTitle)
                    .font(.headline)
                    .lineLimit(1)
                if !row.snippet.isEmpty {
                    Text(row.snippet)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Text(row.updatedAt, format: .relative(presentation: .named))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            AccessibilityLabels.noteRow(
                title: row.displayTitle,
                snippet: row.snippet,
                isPinned: row.isPinned,
                updatedAt: row.updatedAt
            )
        )
        .accessibilityAddTraits(row.isPinned ? [.isSelected] : [])
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
