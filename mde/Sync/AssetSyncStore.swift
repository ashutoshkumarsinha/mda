//
//  AssetSyncStore.swift
//  MDE
//

import Foundation
import GRDB

struct AssetSyncQueueItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: String
    var assetID: String
    var vaultID: String
    var enqueuedAt: Date

    static let databaseTableName = "asset_sync_queue"

    enum Columns: String, ColumnExpression {
        case id, assetID = "asset_id", vaultID = "vault_id", enqueuedAt = "enqueued_at"
    }

    enum CodingKeys: String, CodingKey {
        case id
        case assetID = "asset_id"
        case vaultID = "vault_id"
        case enqueuedAt = "enqueued_at"
    }
}

struct AssetSyncBase: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var assetID: String
    var contentChecksum: String
    var syncedAt: Date

    static let databaseTableName = "asset_sync_base"

    enum Columns: String, ColumnExpression {
        case assetID = "asset_id", contentChecksum = "content_checksum", syncedAt = "synced_at"
    }

    enum CodingKeys: String, CodingKey {
        case assetID = "asset_id"
        case contentChecksum = "content_checksum"
        case syncedAt = "synced_at"
    }
}

enum AssetSyncStore {
    static func enqueue(assetID: String, vaultID: String, in db: Database) throws {
        var item = AssetSyncQueueItem(
            id: UUID().uuidString,
            assetID: assetID,
            vaultID: vaultID,
            enqueuedAt: Date()
        )
        try db.execute(
            sql: "DELETE FROM asset_sync_queue WHERE asset_id = ? AND vault_id = ?",
            arguments: [assetID, vaultID]
        )
        try item.insert(db)
    }

    static func dequeue(assetID: String, vaultID: String, in db: Database) throws {
        try db.execute(
            sql: "DELETE FROM asset_sync_queue WHERE asset_id = ? AND vault_id = ?",
            arguments: [assetID, vaultID]
        )
    }

    static func pendingCount(vaultID: String, in db: Database) throws -> Int {
        try AssetSyncQueueItem
            .filter(AssetSyncQueueItem.Columns.vaultID == vaultID)
            .fetchCount(db)
    }

    static func pendingAssetIDs(vaultID: String, in db: Database) throws -> [String] {
        try AssetSyncQueueItem
            .filter(AssetSyncQueueItem.Columns.vaultID == vaultID)
            .order(AssetSyncQueueItem.Columns.enqueuedAt.asc)
            .fetchAll(db)
            .map(\.assetID)
    }

    static func saveBase(assetID: String, contentChecksum: String, in db: Database) throws {
        var base = AssetSyncBase(assetID: assetID, contentChecksum: contentChecksum, syncedAt: Date())
        try base.save(db)
    }

    static func loadBase(assetID: String, in db: Database) throws -> AssetSyncBase? {
        try AssetSyncBase.filter(AssetSyncBase.Columns.assetID == assetID).fetchOne(db)
    }
}
