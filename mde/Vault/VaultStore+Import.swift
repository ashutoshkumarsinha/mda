//
//  VaultStore+Import.swift
//  MDE
//

import Foundation

extension VaultStore {
    /// Imports a single Markdown file as a new note.
    @discardableResult
    func importMarkdownFile(from url: URL, shouldRewriteEmbeddedImages: Bool = true) throws -> Note {
        let content = try String(contentsOf: url, encoding: .utf8)
        let derivedTitle = url.deletingPathExtension().lastPathComponent
        let title = derivedTitle.isEmpty ? "" : derivedTitle
        var note = try createNote(title: title, content: content)

        if shouldRewriteEmbeddedImages, isPackageAttached {
            let rewritten = try rewriteEmbeddedImages(
                in: content,
                relativeTo: url.deletingLastPathComponent(),
                noteID: note.id
            )
            if rewritten != content {
                note = try updateNote(id: note.id, content: rewritten) ?? note
            }
        }
        return note
    }

    /// Imports every `.md` file in a directory (non-recursive).
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

    /// Recursively imports Markdown notes from a folder, skipping `.obsidian` and copying embedded images into vault assets.
    func importObsidianDirectory(from directoryURL: URL) throws -> [Note] {
        let markdownFiles = try Self.collectObsidianMarkdownFiles(in: directoryURL)
        var imported: [Note] = []
        for fileURL in markdownFiles {
            imported.append(try importMarkdownFile(from: fileURL))
        }
        return imported
    }

    /// Rewrites `![](relative/path)` references to vault `assets/` paths by importing image files.
    func rewriteEmbeddedImages(in content: String, relativeTo baseURL: URL, noteID: String) throws -> String {
        guard isPackageAttached else { return content }

        var result = content
        let references = MarkdownEmbeddedImageParser.externalReferences(in: content)
        for reference in references.reversed() {
            let resolved = baseURL.appendingPathComponent(reference.target).standardizedFileURL
            guard FileManager.default.fileExists(atPath: resolved.path) else { continue }
            let markdown = try importImage(
                from: resolved,
                intoNoteID: noteID,
                altText: reference.alt
            )
            result = (result as NSString).replacingCharacters(in: reference.fullRange, with: markdown)
        }
        return result
    }

    private static func collectObsidianMarkdownFiles(in directoryURL: URL) throws -> [URL] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: directoryURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return []
        }

        var results: [URL] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains(".obsidian") { continue }
            if fileURL.pathExtension.lowercased() == "md" {
                results.append(fileURL)
            }
        }
        return results.sorted {
            $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending
        }
    }
}
