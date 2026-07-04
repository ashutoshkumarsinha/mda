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

    @State private var listScope: NoteListScope = .focused
    @State private var listSort: NoteListSort = .updated
    @State private var displayedRows: [NoteListRow] = []
    @State private var totalNoteCount = 0
    @State private var loadedNoteCount = VaultStore.listPageSize
    @State private var isLoadingMore = false
    @State private var searchResults: [SearchResult] = []
    @State private var errorMessage: String?
    @State private var mergePrimaryNote: NoteListItem?
    @State private var searchTask: Task<Void, Never>?
    @State private var showEmptyTrashConfirmation = false

    private var isTrashView: Bool {
        tagPath == nil && listScope == .trash
    }

    var body: some View {
        Group {
            if isSearching {
                searchResultsList
            } else if displayedRows.isEmpty {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: emptySystemImage,
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
                                if isTrashView {
                                    trashContextMenu(for: row)
                                } else if let note = store.noteSummary(id: row.id) {
                                    noteContextMenu(for: note)
                                } else {
                                    rowContextMenu(for: row)
                                }
                            }
                            .onAppear {
                                if row.id == displayedRows.last?.id {
                                    loadMoreIfNeeded()
                                }
                            }
                    }
                    .onDelete(perform: isTrashView ? purgeNotes : deleteNotes)

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
        .navigationTitle(navigationTitle)
        .accessibilityLabel(isTrashView ? AccessibilityLabels.trashList : AccessibilityLabels.noteList)
        .accessibilityIdentifier("note-list")
        #if os(macOS)
        .focusSection()
        #endif
        .toolbar {
            ToolbarItem {
                Menu {
                    ForEach(NoteListScope.allCases) { scope in
                        Button {
                            listScope = scope
                            reload(resetLoadedWindow: true)
                        } label: {
                            Label(scope.rawValue, systemImage: scope.systemImage)
                        }
                        .disabled(tagPath != nil && scope != .all)
                    }
                } label: {
                    Label(listScope.rawValue, systemImage: listScope.systemImage)
                }
                .disabled(tagPath != nil)
                .accessibilityLabel(AccessibilityLabels.noteListScope(listScope.rawValue))
            }

            if !isTrashView {
                ToolbarItem {
                    Menu {
                        Button("Blank Note", action: addNote)
                        Divider()
                        ForEach(NoteTemplate.allCases.filter { $0 != .blank }) { template in
                            Button {
                                createNote(from: template)
                            } label: {
                                Label(template.rawValue, systemImage: template.systemImage)
                            }
                        }
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                    .accessibilityLabel("New note")
                    .help("Create a new note")
                }

                ToolbarItem {
                    Menu {
                        ForEach(NoteListSort.allCases) { sort in
                            Button {
                                listSort = sort
                                reload(resetLoadedWindow: true)
                            } label: {
                                Label(sort.rawValue, systemImage: sort.systemImage)
                            }
                        }
                    } label: {
                        Label(listSort.rawValue, systemImage: listSort.systemImage)
                    }
                    .accessibilityLabel("Sort notes")
                }
            }

            if isTrashView, !displayedRows.isEmpty {
                ToolbarItem {
                    Button("Empty Trash", role: .destructive) {
                        showEmptyTrashConfirmation = true
                    }
                    .accessibilityLabel(AccessibilityLabels.emptyTrash)
                }
            }
        }
        .onAppear {
            reload(resetLoadedWindow: true)
            bootstrapBenchmarkColdLaunchIfNeeded()
        }
        .onChange(of: tagPath) { _, _ in reload(resetLoadedWindow: true) }
        .onChange(of: listState.revision) { _, _ in reload(resetLoadedWindow: false) }
        .onChange(of: searchQuery) { _, newValue in
            scheduleSearch(query: newValue)
        }
        .background {
            Button("") { addNote() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .hidden()
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
            "Empty Trash?",
            isPresented: $showEmptyTrashConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete \(totalNoteCount) Notes Permanently", role: .destructive) {
                emptyTrash()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Deleted notes will be removed from the vault database.")
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

    private var navigationTitle: String {
        if isTrashView { return "Trash" }
        return "Notes"
    }

    private var emptySystemImage: String {
        if isTrashView { return "trash" }
        return "note.text"
    }

    private var emptyTitle: String {
        if isTrashView { return "Trash is empty" }
        if tagPath != nil { return "No notes match this tag" }
        if listScope == .focused { return "No pinned or recent notes" }
        return "No notes yet"
    }

    private var emptyDescription: String {
        if isTrashView { return "Deleted notes appear here until you empty trash." }
        if tagPath != nil { return "Try another tag or create a note with this tag inline." }
        if listScope == .focused {
            return "Pin notes or edit them within \(NoteListPolicy.recentDays) days, or switch to All Notes."
        }
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

    @ViewBuilder
    private func rowContextMenu(for row: NoteListRow) -> some View {
        Button("Delete", role: .destructive) {
            deleteRow(row)
        }
    }

    @ViewBuilder
    private func trashContextMenu(for row: NoteListRow) -> some View {
        Button("Restore") {
            restoreRow(row)
        }

        Button("Delete Permanently", role: .destructive) {
            purgeRow(row)
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
            let page = try store.noteSummariesPage(
                offset: 0,
                limit: limit,
                tagPath: tagPath,
                scope: listScope,
                sort: listSort
            )
            displayedRows = page.map { NoteListRow(item: $0, store: store) }
            totalNoteCount = try store.noteCountFiltered(by: tagPath, scope: listScope)
            loadedNoteCount = displayedRows.count
            if !isTrashView,
               let selectedNoteID,
               !displayedRows.contains(where: { $0.id == selectedNoteID }) {
                self.selectedNoteID = displayedRows.first?.id
            }
            bootstrapBenchmarkColdLaunchIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadMoreIfNeeded() {
        guard hasMoreNotes, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let next = try store.noteSummariesPage(
                offset: displayedRows.count,
                limit: VaultStore.listPageSize,
                tagPath: tagPath,
                scope: listScope,
                sort: listSort
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
            searchResults = try store.searchNotes(query: query, tagPath: tagPath)
            if let first = searchResults.first {
                selectedNoteID = first.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func bootstrapBenchmarkColdLaunchIfNeeded() {
        guard LaunchArguments.benchmarkColdLaunch else { return }
        if let selectedNoteID,
           displayedRows.contains(where: { $0.id == selectedNoteID }) {
            return
        }
        if let first = displayedRows.first {
            selectedNoteID = first.id
            completeBenchmarkColdLaunchIfPossible(noteID: first.id)
        } else {
            addNote()
            if let selectedNoteID {
                completeBenchmarkColdLaunchIfPossible(noteID: selectedNoteID)
            }
        }
    }

    private func completeBenchmarkColdLaunchIfPossible(noteID: String) {
        guard LaunchArguments.benchmarkColdLaunch else { return }
        if let note = try? store.fetchNote(id: noteID, includeDeleted: true), !note.isDeleted {
            ColdLaunchBenchmark.markEditorReady()
        }
    }

    private func addNote() {
        createNote(from: .blank)
    }

    private func createNote(from template: NoteTemplate) {
        do {
            let note = try store.createNote(content: template.content)
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

    private func purgeNotes(at offsets: IndexSet) {
        let ids = offsets.map { displayedRows[$0].id }
        do {
            for id in ids {
                try store.purgeNote(id: id)
            }
            try store.flushPackageIfNeeded()
            if let selectedNoteID, ids.contains(selectedNoteID) {
                self.selectedNoteID = nil
            }
            reload(resetLoadedWindow: true)
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

    private func deleteRow(_ row: NoteListRow) {
        do {
            try store.softDeleteNote(id: row.id)
            try store.flushPackageIfNeeded()
            if selectedNoteID == row.id {
                selectedNoteID = displayedRows.first(where: { $0.id != row.id })?.id
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func restoreRow(_ row: NoteListRow) {
        do {
            try store.restoreNote(id: row.id)
            try store.flushPackageIfNeeded()
            reload(resetLoadedWindow: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func purgeRow(_ row: NoteListRow) {
        do {
            try store.purgeNote(id: row.id)
            try store.flushPackageIfNeeded()
            if selectedNoteID == row.id {
                selectedNoteID = nil
            }
            reload(resetLoadedWindow: true)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func emptyTrash() {
        do {
            _ = try store.emptyTrash()
            try store.flushPackageIfNeeded()
            selectedNoteID = nil
            reload(resetLoadedWindow: true)
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
