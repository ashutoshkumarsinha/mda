//
//  SyncQueueStore.swift
//  MDE
//

import Foundation
import GRDB

struct SyncQueueItem: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable {
    var id: String
    var noteID: String
    var vaultID: String
    var enqueuedAt: Date

    static let databaseTableName = "sync_queue"

    enum Columns: String, ColumnExpression {
        case id, noteID = "note_id", vaultID = "vault_id", enqueuedAt = "enqueued_at"
    }
}

struct NoteSyncBase: Codable, FetchableRecord, MutablePersistableRecord, Sendable {
    var noteID: String
    var payloadJSON: String

    static let databaseTableName = "note_sync_base"

    enum Columns: String, ColumnExpression {
        case noteID = "note_id", payloadJSON = "payload_json"
    }
}

enum SyncQueueStore {
    static func enqueue(noteID: String, vaultID: String, in db: Database) throws {
        var item = SyncQueueItem(
            id: UUID().uuidString,
            noteID: noteID,
            vaultID: vaultID,
            enqueuedAt: Date()
        )
        try db.execute(
            sql: "DELETE FROM sync_queue WHERE note_id = ? AND vault_id = ?",
            arguments: [noteID, vaultID]
        )
        try item.insert(db)
    }

    static func dequeueAll(vaultID: String, in db: Database) throws -> [SyncQueueItem] {
        let items = try SyncQueueItem
            .filter(SyncQueueItem.Columns.vaultID == vaultID)
            .order(SyncQueueItem.Columns.enqueuedAt.asc)
            .fetchAll(db)
        try db.execute(
            sql: "DELETE FROM sync_queue WHERE vault_id = ?",
            arguments: [vaultID]
        )
        return items
    }

    static func pendingCount(vaultID: String, in db: Database) throws -> Int {
        try SyncQueueItem
            .filter(SyncQueueItem.Columns.vaultID == vaultID)
            .fetchCount(db)
    }

    static func saveBase(_ payload: NoteSyncPayload, in db: Database) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let json = String(data: try encoder.encode(payload), encoding: .utf8) ?? ""
        var base = NoteSyncBase(noteID: payload.noteID, payloadJSON: json)
        try base.save(db)
    }

    static func loadBase(noteID: String, in db: Database) throws -> NoteSyncPayload? {
        guard let row = try NoteSyncBase.filter(NoteSyncBase.Columns.noteID == noteID).fetchOne(db) else {
            return nil
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = row.payloadJSON.data(using: .utf8) else { return nil }
        return try decoder.decode(NoteSyncPayload.self, from: data)
    }
}
