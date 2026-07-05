//
//  VaultStore+Export.swift
//  MDE
//

import Foundation
import GRDB

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

    /// Exports every active note as a portable package: `notes/`, `assets/`, and `meta.json`.
    func makeVaultPackageExportWrapper() throws -> FileWrapper {
        let summaries = try noteSummariesFiltered(by: nil)
        var noteEntries: [VaultExportManifest.NoteEntry] = []
        var noteFiles: [String: FileWrapper] = [:]
        var usedNames = Set<String>()
        var assetsByID: [String: VaultAsset] = [:]

        for summary in summaries {
            guard let note = try fetchNote(id: summary.id) else { continue }
            var filename = exportFilename(for: summary.id)
            while usedNames.contains(filename) {
                filename = "\(UUID().uuidString.prefix(6))-\(filename)"
            }
            usedNames.insert(filename)

            let markdown = Self.markdownExport(for: note)
            let notePath = "\(VaultPackageExport.notesDirectoryName)/\(filename)"
            noteFiles[filename] = FileWrapper(regularFileWithContents: Data(markdown.utf8))
            noteEntries.append(VaultExportManifest.NoteEntry(
                id: note.id,
                title: note.title,
                path: notePath
            ))

            for asset in try exportAssets(for: note) {
                assetsByID[asset.id] = asset
            }
        }

        try validateVaultAssetExport(summaries: summaries, assetsByID: assetsByID)

        let manifest = try makeExportManifest(noteEntries: noteEntries, assets: Array(assetsByID.values))
        let notesWrapper = FileWrapper(directoryWithFileWrappers: noteFiles)
        let assetsWrapper = try makeAssetDirectoryWrapper(for: Array(assetsByID.values))

        var children: [String: FileWrapper] = [
            VaultPackageExport.manifestFileName: FileWrapper(regularFileWithContents: try manifest.data()),
            VaultPackageExport.notesDirectoryName: notesWrapper,
        ]
        if assetsWrapper.fileWrappers?.isEmpty == false {
            children[VaultPackageExport.assetsDirectoryName] = assetsWrapper
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// Folder export alias retained for existing call sites (v2.3 package layout).
    func makeVaultMarkdownExportWrapper() throws -> FileWrapper {
        try makeVaultPackageExportWrapper()
    }

    /// Zip archive of the portable vault package (`notes/`, `assets/`, `meta.json`).
    func makeVaultZipExportData() throws -> Data {
        try ZipArchiveBuilder.zipData(from: makeVaultPackageExportWrapper())
    }

    /// Exports one note and its linked assets as a folder package.
    func makeNotePackageExportWrapper(noteID: String) throws -> FileWrapper {
        guard let note = try fetchNote(id: noteID) else {
            throw VaultExportError.noteNotFound
        }

        let assets = try exportAssets(for: note)
        try validateAssetExport(for: note, assets: assets)

        let filename = exportFilename(for: note.id)
        let notePath = filename
        let manifest = try makeExportManifest(
            noteEntries: [VaultExportManifest.NoteEntry(id: note.id, title: note.title, path: notePath)],
            assets: assets
        )

        var children: [String: FileWrapper] = [
            VaultPackageExport.manifestFileName: FileWrapper(regularFileWithContents: try manifest.data()),
            filename: FileWrapper(regularFileWithContents: Data(Self.markdownExport(for: note).utf8)),
        ]

        let assetsWrapper = try makeAssetDirectoryWrapper(for: assets)
        if assetsWrapper.fileWrappers?.isEmpty == false {
            children[VaultPackageExport.assetsDirectoryName] = assetsWrapper
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    /// Zip archive of a single-note package export.
    func makeNoteZipExportData(noteID: String) throws -> Data {
        try ZipArchiveBuilder.zipData(from: makeNotePackageExportWrapper(noteID: noteID))
    }

    /// PDF export for a single note (plain-text layout).
    func makeNotePDFExportData(noteID: String) throws -> Data {
        guard let note = try fetchNote(id: noteID) else {
            throw VaultStoreError.noteNotFound
        }
        return try NotePDFExporter.pdfData(title: note.title, body: note.content)
    }

    /// Single-file vault export for quick sharing.
    func exportVaultAsCombinedMarkdown() throws -> String {
        let summaries = try noteSummariesFiltered(by: nil)
        return try summaries.compactMap { summary -> String? in
            guard let note = try fetchNote(id: summary.id) else { return nil }
            return "<!-- note-id: \(note.id) -->\n" + Self.markdownExport(for: note)
        }.joined(separator: "\n\n---\n\n")
    }

    private func exportAssets(for note: Note) throws -> [VaultAsset] {
        var assetsByID: [String: VaultAsset] = [:]

        for asset in try assetsLinkedToNote(id: note.id) {
            assetsByID[asset.id] = asset
        }

        for reference in MarkdownImageExtractor.references(in: note.content) {
            if let asset = try fetchAsset(filename: reference.assetFilename) {
                assetsByID[asset.id] = asset
            }
        }

        return assetsByID.values.sorted { $0.createdAt < $1.createdAt }
    }

    private func makeExportManifest(
        noteEntries: [VaultExportManifest.NoteEntry],
        assets: [VaultAsset]
    ) throws -> VaultExportManifest {
        VaultExportManifest(
            exportVersion: VaultExportManifest.exportVersion,
            vaultID: meta.vaultID,
            exportedAt: Date(),
            notes: noteEntries,
            assets: assets.map {
                VaultExportManifest.AssetEntry(
                    id: $0.id,
                    path: "\(VaultPackageExport.assetsDirectoryName)/\($0.filename)",
                    mimeType: $0.mimeType
                )
            }
        )
    }

    private func makeAssetDirectoryWrapper(for assets: [VaultAsset]) throws -> FileWrapper {
        guard !assets.isEmpty else {
            return FileWrapper(directoryWithFileWrappers: [:])
        }
        guard let packageURL = attachedPackageURL else {
            throw VaultExportError.assetsUnavailable
        }

        var children: [String: FileWrapper] = [:]
        for asset in assets {
            let data = try VaultAssetStore.readAssetData(asset: asset, packageURL: packageURL)
            children[asset.filename] = FileWrapper(regularFileWithContents: data)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }

    private func validateAssetExport(for note: Note, assets: [VaultAsset]) throws {
        let referenced = referencedAssetFilenames(in: note.content)
        guard !referenced.isEmpty else { return }
        guard isPackageAttached else {
            throw VaultExportError.assetsUnavailable
        }
        let exported = Set(assets.map(\.filename))
        if referenced.contains(where: { !exported.contains($0) }) {
            throw VaultExportError.assetsUnavailable
        }
    }

    private func validateVaultAssetExport(
        summaries: [NoteListItem],
        assetsByID: [String: VaultAsset]
    ) throws {
        let exported = Set(assetsByID.values.map(\.filename))
        for summary in summaries {
            guard let note = try fetchNote(id: summary.id) else { continue }
            let referenced = referencedAssetFilenames(in: note.content)
            guard !referenced.isEmpty else { continue }
            guard isPackageAttached else {
                throw VaultExportError.assetsUnavailable
            }
            if referenced.contains(where: { !exported.contains($0) }) {
                throw VaultExportError.assetsUnavailable
            }
        }
    }

    private func referencedAssetFilenames(in content: String) -> [String] {
        MarkdownImageExtractor.references(in: content).map(\.assetFilename)
    }

    private static func sanitizeFilename(_ name: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        let cleaned = name.components(separatedBy: invalid).joined(separator: "-")
        let collapsed = cleaned.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed.isEmpty ? "Untitled" : String(collapsed.prefix(80))
    }
}
