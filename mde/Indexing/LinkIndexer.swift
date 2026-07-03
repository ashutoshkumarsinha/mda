//
//  LinkIndexer.swift
//  MDE
//

import Foundation
import GRDB

enum LinkIndexer {
    static func reindexLinks(for noteID: String, content: String, in db: Database) throws {
        let titles = WikiLinkExtractor.extractTitles(from: content)

        try db.execute(sql: "DELETE FROM note_link WHERE source_id = ?", arguments: [noteID])

        for title in titles {
            let linkID = UUID().uuidString
            let targetID = try resolveTargetID(title: title, in: db)
            try db.execute(
                sql: """
                INSERT INTO note_link (id, source_id, target_title, target_id)
                VALUES (?, ?, ?, ?)
                """,
                arguments: [linkID, noteID, title, targetID]
            )
        }

        try resolvePendingLinks(in: db)
    }

    static func resolvePendingLinks(in db: Database) throws {
        let pending = try Row.fetchAll(db, sql: """
            SELECT id, target_title FROM note_link WHERE target_id IS NULL
        """)

        for row in pending {
            let linkID: String = row["id"]
            let title: String = row["target_title"]
            if let targetID = try resolveTargetID(title: title, in: db) {
                try db.execute(
                    sql: "UPDATE note_link SET target_id = ? WHERE id = ?",
                    arguments: [targetID, linkID]
                )
            }
        }
    }

    static func fetchBacklinks(for noteID: String, title: String, in db: Database) throws -> [Note] {
        try Note.fetchAll(db, sql: """
            SELECT n.*
            FROM note n
            JOIN note_link nl ON nl.source_id = n.id
            WHERE (nl.target_id = ? OR LOWER(nl.target_title) = LOWER(?))
              AND n.is_deleted = 0
            ORDER BY n.is_pinned DESC, n.updated_at DESC
        """, arguments: [noteID, title])
    }

    private static func resolveTargetID(title: String, in db: Database) throws -> String? {
        try String.fetchOne(db, sql: """
            SELECT id FROM note
            WHERE is_deleted = 0 AND LOWER(title) = LOWER(?)
            LIMIT 1
        """, arguments: [title])
    }
}
