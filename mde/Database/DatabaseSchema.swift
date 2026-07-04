//
//  DatabaseSchema.swift
//  MDE
//

import Foundation
import GRDB

enum DatabaseSchema {
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        #if DEBUG
        migrator.eraseDatabaseOnSchemaChange = true
        #endif

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "note") { t in
                t.autoIncrementedPrimaryKey("rowid")
                t.column("id", .text).notNull().unique()
                t.column("title", .text).notNull().defaults(to: "")
                t.column("content", .text).notNull().defaults(to: "")
                t.column("created_at", .datetime).notNull()
                t.column("updated_at", .datetime).notNull()
                t.column("is_pinned", .boolean).notNull().defaults(to: false)
                t.column("is_deleted", .boolean).notNull().defaults(to: false)
                t.column("version", .integer).notNull().defaults(to: 1)
                t.column("client_updated_at", .datetime).notNull()
                t.column("checksum", .text).notNull().defaults(to: "")
            }
            try db.create(index: "idx_note_id", on: "note", columns: ["id"])
            try db.create(index: "idx_note_updated_at", on: "note", columns: ["updated_at"])
            try db.create(index: "idx_note_is_pinned", on: "note", columns: ["is_pinned"])

            try db.execute(sql: """
            CREATE VIRTUAL TABLE note_fts USING fts5(
                title,
                content,
                content='note',
                content_rowid='rowid',
                tokenize='porter unicode61'
            );
            """)

            try db.execute(sql: """
            CREATE TRIGGER note_ai AFTER INSERT ON note BEGIN
                INSERT INTO note_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END;
            CREATE TRIGGER note_ad AFTER DELETE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
            END;
            CREATE TRIGGER note_au AFTER UPDATE ON note BEGIN
                INSERT INTO note_fts(note_fts, rowid, title, content)
                VALUES ('delete', old.rowid, old.title, old.content);
                INSERT INTO note_fts(rowid, title, content)
                VALUES (new.rowid, new.title, new.content);
            END;
            """)

            try db.create(table: "tag") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("path", .text).notNull()
                t.column("parent_id", .text).references("tag", onDelete: .cascade)
                t.uniqueKey(["path"])
            }
            try db.create(index: "idx_tag_parent_id", on: "tag", columns: ["parent_id"])

            try db.execute(sql: """
            CREATE TABLE note_tag (
                note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                tag_id TEXT NOT NULL REFERENCES tag(id) ON DELETE CASCADE,
                PRIMARY KEY (note_id, tag_id)
            );
            """)
            try db.create(index: "idx_note_tag_tag_id", on: "note_tag", columns: ["tag_id"])

            try db.execute(sql: """
            CREATE TABLE note_link (
                id TEXT PRIMARY KEY NOT NULL,
                source_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                target_title TEXT NOT NULL,
                target_id TEXT REFERENCES note(id) ON DELETE SET NULL,
                UNIQUE (source_id, target_title)
            );
            """)
            try db.create(index: "idx_note_link_source", on: "note_link", columns: ["source_id"])
            try db.create(index: "idx_note_link_target", on: "note_link", columns: ["target_id"])
            try db.create(index: "idx_note_link_target_title", on: "note_link", columns: ["target_title"])

            try db.create(table: "sync_queue") { t in
                t.column("id", .text).primaryKey()
                t.column("note_id", .text).notNull()
                t.column("vault_id", .text).notNull()
                t.column("enqueued_at", .datetime).notNull()
            }
            try db.create(index: "idx_sync_queue_vault", on: "sync_queue", columns: ["vault_id"])

            try db.create(table: "note_sync_base") { t in
                t.column("note_id", .text).primaryKey()
                t.column("payload_json", .text).notNull()
            }
        }

        migrator.registerMigration("v2_list_query_index") { db in
            try db.create(
                index: "idx_note_list_order",
                on: "note",
                columns: ["is_deleted", "is_pinned", "updated_at"]
            )
        }

        migrator.registerMigration("v3_vault_assets") { db in
            try db.create(table: "vault_asset") { t in
                t.column("id", .text).primaryKey()
                t.column("filename", .text).notNull()
                t.column("mime_type", .text).notNull()
                t.column("byte_size", .integer).notNull()
                t.column("created_at", .datetime).notNull()
            }
            try db.create(index: "idx_vault_asset_filename", on: "vault_asset", columns: ["filename"])

            try db.execute(sql: """
            CREATE TABLE note_asset (
                note_id TEXT NOT NULL REFERENCES note(id) ON DELETE CASCADE,
                asset_id TEXT NOT NULL REFERENCES vault_asset(id) ON DELETE CASCADE,
                alt_text TEXT NOT NULL DEFAULT '',
                PRIMARY KEY (note_id, asset_id)
            );
            """)
            try db.create(index: "idx_note_asset_asset_id", on: "note_asset", columns: ["asset_id"])
        }

        return migrator
    }

    private static let migrationIdentifiers = [
        "v1_initial_schema",
        "v2_list_query_index",
        "v3_vault_assets",
    ]

    static func migrate(_ dbQueue: DatabaseQueue, databaseURL: URL? = nil) throws {
        if let databaseURL {
            let fileManager = FileManager.default
            if fileManager.fileExists(atPath: databaseURL.path) {
                let backupURL = VaultPaths.backupDatabaseURL(in: databaseURL.deletingLastPathComponent())
                let hasPending = try dbQueue.read { db in
                    try hasPendingMigrations(on: db)
                }
                let needsInitialBackup = !fileManager.fileExists(atPath: backupURL.path)
                if hasPending || needsInitialBackup {
                    try backupDatabaseIfNeeded(at: databaseURL)
                }
            }
        }
        try migrator.migrate(dbQueue)
    }

    private static func hasPendingMigrations(on db: Database) throws -> Bool {
        let applied = try migrator.appliedIdentifiers(db)
        return migrationIdentifiers.contains { !applied.contains($0) }
    }

    private static func backupDatabaseIfNeeded(at databaseURL: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else { return }

        let backupURL = VaultPaths.backupDatabaseURL(in: databaseURL.deletingLastPathComponent())
        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        try fileManager.copyItem(at: databaseURL, to: backupURL)
    }
}
