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
    static let exportNote = "Export note"
    static let insertImage = "Insert image into note"
    static let emptyTrash = "Empty trash permanently"
    static let backlinksPanel = "Backlinks panel"
    static let emptyBacklinks = "No notes link here yet"
    static let trashedNoteReadOnly = "Trashed note, read only"
    static let vaultMenu = "Vault actions menu"
    static let graphCanvas = "Wiki link graph"
    static let graphLegend = "Graph legend: notes and unresolved links"
    static let graphLayoutPicker = "Graph layout style"
    static let graphFocusToggle = "Focus on selected note neighborhood"
    static let graphFitView = "Fit graph to view"
    static let graphReload = "Reload link graph"

    static func graphNode(title: String, isUnresolved: Bool, linkCount: Int) -> String {
        if isUnresolved {
            return "Unresolved link \(title), \(linkCount) connections"
        }
        return "Note \(title), \(linkCount) connections"
    }

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
