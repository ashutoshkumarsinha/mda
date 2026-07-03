//
//  NoteListRow.swift
//  MDE
//

import Foundation

/// Precomputed list row for stable `Equatable` diffing in SwiftUI.
struct NoteListRow: Identifiable, Equatable, Sendable {
    let id: String
    let displayTitle: String
    let snippet: String
    let updatedAt: Date
    let isPinned: Bool
    let rowIdentity: String

    init(item: NoteListItem, store: VaultStore) {
        id = item.id
        displayTitle = store.noteDisplayTitle(item)
        snippet = store.noteSnippet(item)
        updatedAt = item.updatedAt
        isPinned = item.isPinned
        rowIdentity = "\(item.id)-\(item.updatedAt.timeIntervalSinceReferenceDate)"
    }
}
