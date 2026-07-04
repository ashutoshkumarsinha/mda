//
//  VaultPackageImporter.swift
//  MDE
//

import Foundation
import GRDB

enum VaultPackageImporter {
    static func isExportPackage(at url: URL) -> Bool {
        let metaURL = url.appendingPathComponent(VaultPackageExport.manifestFileName)
        guard let data = try? Data(contentsOf: metaURL) else { return false }
        return (try? VaultExportManifest.decode(from: data)) != nil
    }

    static func importPackage(at rootURL: URL, into store: VaultStore) throws -> [Note] {
        let manifestURL = rootURL.appendingPathComponent(VaultPackageExport.manifestFileName)
        let manifest = try VaultExportManifest.decode(from: Data(contentsOf: manifestURL))
        guard manifest.exportVersion == VaultExportManifest.exportVersion else {
            throw VaultImportError.unsupportedExportVersion(manifest.exportVersion)
        }

        if store.isPackageAttached, let packageURL = store.attachedPackageURL {
            try importAssets(from: rootURL, manifest: manifest, into: store, packageURL: packageURL)
        }

        var imported: [Note] = []
        for entry in manifest.notes.sorted(by: { $0.path.localizedCaseInsensitiveCompare($1.path) == .orderedAscending }) {
            let noteURL = rootURL.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: noteURL.path) else { continue }
            let rawContent = try String(contentsOf: noteURL, encoding: .utf8)
            let content = normalizedImportContent(rawContent, title: entry.title)
            let note = try store.createNote(title: entry.title, content: content)
            imported.append(note)
        }
        return imported
    }

    private static func importAssets(
        from rootURL: URL,
        manifest: VaultExportManifest,
        into store: VaultStore,
        packageURL: URL
    ) throws {
        let dbQueue = try store.requireDatabaseQueue()
        for entry in manifest.assets {
            let sourceURL = rootURL.appendingPathComponent(entry.path)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }

            let filename = (entry.path as NSString).lastPathComponent
            guard VaultAssetStore.parseVaultAssetPath("assets/\(filename)") != nil else { continue }

            let data = try Data(contentsOf: sourceURL)
            var asset = VaultAsset(
                id: entry.id,
                filename: filename,
                mimeType: entry.mimeType,
                byteSize: Int64(data.count),
                createdAt: Date()
            )

            try VaultAssetStore.writeAsset(data: data, asset: asset, packageURL: packageURL)
            try dbQueue.write { db in
                if var existing = try VaultAsset.fetchOne(db, key: entry.id) {
                    existing.filename = filename
                    existing.mimeType = entry.mimeType
                    existing.byteSize = asset.byteSize
                    try existing.update(db)
                } else {
                    try asset.insert(db)
                }
            }
        }
        store.markPackageDirty()
    }

    /// Strips a leading `# Title` line when it duplicates the manifest title (v2.3 export adds one).
    private static func normalizedImportContent(_ content: String, title: String) -> String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTitle.isEmpty else { return content }

        let lines = content.components(separatedBy: "\n")
        var index = 0
        while index < lines.count, lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            index += 1
        }
        guard index < lines.count else { return content }

        let line = lines[index].trimmingCharacters(in: .whitespaces)
        guard line.hasPrefix("#") else { return content }

        let heading = String(line.drop(while: { $0 == "#" || $0 == " " }))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard heading.caseInsensitiveCompare(trimmedTitle) == .orderedSame else { return content }

        return lines.dropFirst(index + 1).joined(separator: "\n").trimmingCharacters(in: .newlines)
    }
}

enum VaultImportError: LocalizedError {
    case packageRequired
    case unsupportedExportVersion(Int)
    case invalidZipArchive

    var errorDescription: String? {
        switch self {
        case .packageRequired:
            return "Save the vault to a package before importing images from an export."
        case .unsupportedExportVersion(let version):
            return "Unsupported export format version \(version)."
        case .invalidZipArchive:
            return "The zip file is not a valid MDE export archive."
        }
    }
}
