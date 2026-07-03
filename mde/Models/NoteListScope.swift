//
//  NoteListScope.swift
//  MDE
//

import Foundation

/// Working-set filter for the note list column.
enum NoteListScope: String, CaseIterable, Identifiable, Sendable {
    case focused = "Pinned & Recent"
    case all = "All Notes"
    case trash = "Trash"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .focused: "star.circle"
        case .all: "note.text"
        case .trash: "trash"
        }
    }
}

enum NoteListPolicy {
    /// Notes updated within this window appear in the focused list (unpinned).
    static let recentDays = 30
}
