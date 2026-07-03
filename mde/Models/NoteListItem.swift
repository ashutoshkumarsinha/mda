//
//  NoteListItem.swift
//  MDE
//

import Foundation

/// Lightweight note row for list/sidebar — no body text in memory.
struct NoteListItem: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var snippet: String
    var updatedAt: Date
    var isPinned: Bool

    init(id: String, title: String, snippet: String, updatedAt: Date, isPinned: Bool) {
        self.id = id
        self.title = title
        self.snippet = snippet
        self.updatedAt = updatedAt
        self.isPinned = isPinned
    }

    init(note: Note, snippet: String) {
        id = note.id
        title = note.title
        self.snippet = snippet
        updatedAt = note.updatedAt
        isPinned = note.isPinned
    }

    static func makeSnippet(from content: String, maxLength: Int = 120) -> String {
        let text = content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }

    func displayTitle(fallbackContent: String = "") -> String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let content = fallbackContent.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return String(content.prefix(80)) }
        if !snippet.isEmpty { return String(snippet.prefix(80)) }
        return "Untitled"
    }
}
