//
//  VaultStore+Assets.swift
//  MDE
//

import Foundation
import GRDB

extension VaultStore {
    /// Imports an image into the vault package and links it to a note. Returns markdown to insert.
    @discardableResult
    func importImage(
        from sourceURL: URL,
        intoNoteID noteID: String,
        altText: String = ""
    ) throws -> String {
        guard isPackageAttached, let packageURL = attachedPackageURL else {
            throw VaultAssetError.packageNotAttached
        }
        guard try fetchNote(id: noteID, includeDeleted: true) != nil else {
            throw VaultStoreError.noteNotFound
        }

        let accessing = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }

        guard let ext = VaultAssetStore.normalizedExtension(for: sourceURL),
              let mimeType = VaultAssetStore.mimeType(forExtension: ext) else {
            throw VaultAssetError.unsupportedImageType(sourceURL.pathExtension)
        }

        let data = try Data(contentsOf: sourceURL)
        let assetID = UUID().uuidString
        let filename = "\(assetID).\(ext)"
        var asset = VaultAsset(
            id: assetID,
            filename: filename,
            mimeType: mimeType,
            byteSize: Int64(data.count),
            createdAt: Date()
        )

        try VaultAssetStore.writeAsset(data: data, asset: asset, packageURL: packageURL)

        let dbQueue = try requireDatabaseQueue()
        try dbQueue.write { db in
            try asset.insert(db)
            var link = NoteAsset(noteID: noteID, assetID: assetID, altText: altText)
            try link.insert(db)
        }

        return VaultAssetStore.markdownReference(alt: altText, asset: asset)
    }

    func assetURL(forMarkdownPath path: String) -> URL? {
        guard let packageURL = attachedPackageURL,
              let filename = VaultAssetStore.parseVaultAssetPath(path) else {
            return nil
        }
        let url = VaultPaths.assetFileURL(in: packageURL, filename: filename)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func fetchAsset(id: String) throws -> VaultAsset? {
        let dbQueue = try requireDatabaseQueue()
        return try dbQueue.read { db in
            try VaultAsset.fetchOne(db, key: id)
        }
    }

    func assetsLinkedToNote(id: String) throws -> [VaultAsset] {
        let dbQueue = try requireDatabaseQueue()
        return try dbQueue.read { db in
            try VaultAsset.fetchAll(db, sql: """
                SELECT vault_asset.*
                FROM vault_asset
                INNER JOIN note_asset ON note_asset.asset_id = vault_asset.id
                WHERE note_asset.note_id = ?
                ORDER BY vault_asset.created_at
            """, arguments: [id])
        }
    }
}
