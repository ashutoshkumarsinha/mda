//
//  VaultStore+AssetSync.swift
//  MDE
//

import Foundation
import GRDB

extension VaultStore {
    func enqueueAssetSync(assetID: String) throws {
        guard meta.syncEnabled else { return }
        let dbQueue = try requireDatabaseQueue()
        try dbQueue.write { db in
            try AssetSyncStore.enqueue(assetID: assetID, vaultID: meta.vaultID, in: db)
        }
    }

    /// Enqueues upload for every vault asset referenced in a note's markdown.
    func enqueueAssetSyncForNoteReferences(noteID: String) throws {
        guard meta.syncEnabled,
              let note = try fetchNote(id: noteID) else { return }

        var enqueued = Set<String>()
        for reference in MarkdownImageExtractor.references(in: note.content) {
            if let asset = try fetchAsset(filename: reference.assetFilename),
               enqueued.insert(asset.id).inserted {
                try enqueueAssetSync(assetID: asset.id)
            }
        }
    }

    /// Asset IDs referenced in content whose files are not present locally.
    func missingReferencedAssetIDs(in content: String) -> [String] {
        MarkdownImageExtractor.references(in: content).compactMap { reference in
            guard !assetFileExists(filename: reference.assetFilename) else { return nil }
            return (reference.assetFilename as NSString).deletingPathExtension
        }
    }

    func dequeueAssetSync(assetID: String) throws {
        let dbQueue = try requireDatabaseQueue()
        try dbQueue.write { db in
            try AssetSyncStore.dequeue(assetID: assetID, vaultID: meta.vaultID, in: db)
        }
    }

    func pendingAssetSyncCount() throws -> Int {
        guard let dbQueue = try? requireDatabaseQueue() else { return 0 }
        return try dbQueue.read { db in
            try AssetSyncStore.pendingCount(vaultID: meta.vaultID, in: db)
        }
    }

    func pendingAssetSyncPayloads() throws -> [(AssetSyncPayload, Data)] {
        guard let dbQueue = try? requireDatabaseQueue() else { return [] }

        return try dbQueue.read { db in
            let assetIDs = try AssetSyncStore.pendingAssetIDs(vaultID: meta.vaultID, in: db)
            guard !assetIDs.isEmpty else { return [] }
            guard let packageURL = attachedPackageURL else {
                throw SyncError.assetUnavailable
            }

            var results: [(AssetSyncPayload, Data)] = []
            for assetID in assetIDs {
                guard let asset = try VaultAsset.fetchOne(db, key: assetID) else { continue }
                let data = try VaultAssetStore.readAssetData(asset: asset, packageURL: packageURL)
                let checksum = AssetSyncChecksum.compute(for: data)
                let payload = AssetSyncPayload(asset: asset, vaultID: meta.vaultID, contentChecksum: checksum)
                results.append((payload, data))
            }
            return results
        }
    }

    func assetSyncBaseChecksum(for assetID: String) throws -> String? {
        guard let dbQueue = try? requireDatabaseQueue() else { return nil }
        return try dbQueue.read { db in
            try AssetSyncStore.loadBase(assetID: assetID, in: db)?.contentChecksum
        }
    }

    func saveAssetSyncBase(assetID: String, contentChecksum: String) throws {
        let dbQueue = try requireDatabaseQueue()
        try dbQueue.write { db in
            try AssetSyncStore.saveBase(assetID: assetID, contentChecksum: contentChecksum, in: db)
        }
    }

    /// Applies a remote asset when the local copy is missing or checksum differs.
    /// Assets are keyed by immutable `asset_id`; content is replaced only when checksum changes.
    func applyRemoteAsset(_ payload: AssetSyncPayload, data: Data) throws {
        guard payload.contentChecksum == AssetSyncChecksum.compute(for: data) else {
            throw SyncError.decryptionFailed
        }
        guard let packageURL = attachedPackageURL else {
            throw SyncError.assetUnavailable
        }

        let dbQueue = try requireDatabaseQueue()
        let alreadySynced = try dbQueue.read { db in
            try AssetSyncStore.loadBase(assetID: payload.assetID, in: db)?.contentChecksum == payload.contentChecksum
        }
        if alreadySynced {
            return
        }

        try dbQueue.write { db in
            if var existing = try VaultAsset.fetchOne(db, key: payload.assetID) {
                existing.filename = payload.filename
                existing.mimeType = payload.mimeType
                existing.byteSize = payload.byteSize
                try existing.update(db)
            } else {
                var asset = VaultAsset(
                    id: payload.assetID,
                    filename: payload.filename,
                    mimeType: payload.mimeType,
                    byteSize: payload.byteSize,
                    createdAt: payload.createdAt
                )
                try asset.insert(db)
            }
        }

        let asset = VaultAsset(
            id: payload.assetID,
            filename: payload.filename,
            mimeType: payload.mimeType,
            byteSize: payload.byteSize,
            createdAt: payload.createdAt
        )
        try VaultAssetStore.writeAsset(data: data, asset: asset, packageURL: packageURL)
        try saveAssetSyncBase(assetID: payload.assetID, contentChecksum: payload.contentChecksum)
        markPackageDirty()
    }
}
