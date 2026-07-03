//
//  AccessibilityLabels.swift
//  MDE
//

import Foundation

enum AccessibilityLabels {
    static let tagSidebar = "Tags"
    static let noteList = "Notes"
    static let trashList = "Trash"
    static let noteEditor = "Note editor"
    static let exportNote = "Export note as Markdown"
    static let emptyTrash = "Empty trash permanently"
    static let backlinksPanel = "Backlinks panel"
    static let emptyBacklinks = "No notes link here yet"
    static let allTagsFilter = "All notes, show every tag"

    static func noteListScope(_ scope: String) -> String {
        "Note list filter, \(scope)"
    }

    static func tagFilter(path: String, isSelected: Bool) -> String {
        let selection = isSelected ? "selected" : "not selected"
        return "Tag \(path), \(selection)"
    }

    static func noteRow(title: String, snippet: String, isPinned: Bool, updatedAt: Date) -> String {
        var parts = [title]
        if isPinned { parts.append("pinned") }
        if !snippet.isEmpty { parts.append(snippet) }
        parts.append("updated \(updatedAt.formatted(.relative(presentation: .named)))")
        return parts.joined(separator: ", ")
    }

    static func searchResult(title: String, snippet: String) -> String {
        if snippet.isEmpty { return "Search result \(title)" }
        return "Search result \(title), \(snippet)"
    }

    static func backlink(title: String) -> String {
        "Backlink to \(title)"
    }

    static func taskCheckbox(checked: Bool) -> String {
        checked ? "Task checkbox, checked" : "Task checkbox, unchecked"
    }

    static func editorPlaceholder(noteTitle: String) -> String {
        "Editing \(noteTitle)"
    }

    static let emptyNoteSelection = "Select a note to edit"

    static func syncStatus(_ status: String, pendingCount: Int) -> String {
        if pendingCount > 0 {
            return "Sync status \(status), \(pendingCount) pending changes"
        }
        return "Sync status \(status)"
    }
}
