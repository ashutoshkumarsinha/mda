//
//  VaultStore+Export.swift
//  MDE
//

import Foundation

extension VaultStore {
    /// Exports a single note as Markdown without reading the full vault.
    func exportNoteAsMarkdown(id: String) throws -> String {
        guard let note = try fetchNote(id: id) else {
            throw VaultStoreError.noteNotFound
        }
        return Self.markdownExport(for: note)
    }

    /// Suggested filename for a note export (sanitized title).
    func exportFilename(for noteID: String) -> String {
        let title = noteSummary(id: noteID)?.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = (title?.isEmpty == false) ? title! : "Untitled"
        let sanitized = Self.sanitizeFilename(base)
        return "\(sanitized).md"
    }

    static func markdownExport(for note: Note) -> String {
        let trimmedContent = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedTitle = note.title.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedTitle.isEmpty {
            return note.content
        }
        if trimmedContent.hasPrefix("#") {
            return note.content
        }
        return "# \(trimmedTitle)\n\n\(note.content)"
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Untitled" : String(collapsed.prefix(80))
    }
}
