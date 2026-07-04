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

    /// Exports every active note as Markdown files in a directory wrapper (no full DB export).
    func makeVaultMarkdownExportWrapper() throws -> FileWrapper {
        let summaries = try noteSummariesFiltered(by: nil)
        var children: [String: FileWrapper] = [:]
        var usedNames = Set<String>()

        for summary in summaries {
            guard let note = try fetchNote(id: summary.id) else { continue }
            var filename = exportFilename(for: summary.id)
            while usedNames.contains(filename) {
                filename = "\(UUID().uuidString.prefix(6))-\(filename)"
            }
            usedNames.insert(filename)
            let markdown = Self.markdownExport(for: note)
            children[filename] = FileWrapper(regularFileWithContents: Data(markdown.utf8))
        }

        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// Single-file vault export for quick sharing.
    func exportVaultAsCombinedMarkdown() throws -> String {
        let summaries = try noteSummariesFiltered(by: nil)
        return try summaries.compactMap { summary -> String? in
            guard let note = try fetchNote(id: summary.id) else { return nil }
            return "<!-- note-id: \(note.id) -->\n" + Self.markdownExport(for: note)
        }.joined(separator: "\n\n---\n\n")
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Untitled" : String(collapsed.prefix(80))
    }
}
