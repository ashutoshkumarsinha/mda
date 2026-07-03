//
//  ContentView.swift
//  MDE
//

import SwiftUI

struct ContentView: View {
    @Bindable var store: VaultStore
    @State private var errorMessage: String?

    var body: some View {
        NavigationSplitView {
            Group {
                if store.notes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet",
                        systemImage: "note.text",
                        description: Text("Create your first note to get started.")
                    )
                } else {
                    List {
                        ForEach(store.notes) { note in
                            NavigationLink {
                                NoteDetailView(note: note)
                            } label: {
                                NoteRowView(note: note)
                            }
                        }
                        .onDelete(perform: deleteNotes)
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
            .toolbar {
                ToolbarItem {
                    Button(action: addNote) {
                        Label("New Note", systemImage: "plus")
                    }
                }
            }
        } detail: {
            Text("Select a note")
                .foregroundStyle(.secondary)
        }
        .alert("Vault Error", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addNote() {
        do {
            _ = try store.createNote(title: "Untitled")
            try store.persistToPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteNotes(at offsets: IndexSet) {
        do {
            try store.softDeleteNotes(at: offsets)
            try store.persistToPackageIfNeeded()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct NoteRowView: View {
    let note: Note

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(displayTitle)
                .font(.headline)
            Text(note.updatedAt, format: .relative(presentation: .named))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return String(content.prefix(80)) }
        return "Untitled"
    }
}

private struct NoteDetailView: View {
    let note: Note

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(displayTitle)
                    .font(.title2.bold())
                Text(note.content.isEmpty ? "Empty note" : note.content)
                    .font(.body)
                    .foregroundStyle(note.content.isEmpty ? .secondary : .primary)
                Text("Updated \(note.updatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle(displayTitle)
    }

    private var displayTitle: String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }
}

#Preview {
    ContentView(store: VaultStore())
}
