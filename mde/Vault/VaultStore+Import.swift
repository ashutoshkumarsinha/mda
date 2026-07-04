//
//  VaultStore+Import.swift
//  MDE
//

import Foundation

extension VaultStore {
    /// Imports a single Markdown file as a new note.
    @discardableResult
    func importMarkdownFile(from url: URL) throws -> Note {
        let content = try String(contentsOf: url, encoding: .utf8)
        let derivedTitle = url.deletingPathExtension().lastPathComponent
        let title = derivedTitle.isEmpty ? "" : derivedTitle
        return try createNote(title: title, content: content)
    }

    /// Imports every `.md` file in a directory (Obsidian / plain Markdown folders).
    func importMarkdownDirectory(from directoryURL: URL) throws -> [Note] {
        let fileManager = FileManager.default
        let markdownFiles = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension.lowercased() == "md" }
        .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }

        var imported: [Note] = []
        for fileURL in markdownFiles {
            imported.append(try importMarkdownFile(from: fileURL))
        }
        return imported
    }
}
