//
//  VaultStore+ListQuery.swift
//  MDE
//

import Foundation
import GRDB

extension VaultStore {
    static let listPageSize = 100

    static let listItemSelectSQL = """
        SELECT n.id, n.title, n.updated_at, n.is_pinned,
               trim(substr(replace(n.content, char(10), ' '), 1, 120)) AS snippet
    """

    static func mapListItemRow(_ row: Row) -> NoteListItem {
        NoteListItem(
            id: row["id"],
            title: row["title"],
            snippet: row["snippet"] ?? "",
            updatedAt: row["updated_at"],
            isPinned: row["is_pinned"]
        )
    }

    func fetchNoteSummariesFiltered(by tagPath: String?, in db: Database) throws -> [NoteListItem] {
        try fetchNoteSummariesPage(offset: 0, limit: Int.max, tagPath: tagPath, in: db)
    }

    func fetchNoteSummariesPage(
        offset: Int,
        limit: Int,
        tagPath: String?,
        in db: Database
    ) throws -> [NoteListItem] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, limit)

        if let tagPath {
            return try PerformanceSignpost.measure(.vaultListPage) {
                try Row.fetchAll(db, sql: """
                    \(Self.listItemSelectSQL)
                    FROM note n
                    JOIN note_tag nt ON nt.note_id = n.id
                    JOIN tag t ON t.id = nt.tag_id
                    WHERE n.is_deleted = 0
                      AND (t.path = ? OR t.path LIKE ?)
                    GROUP BY n.id
                    ORDER BY n.is_pinned DESC, n.updated_at DESC
                    LIMIT ? OFFSET ?
                """, arguments: [tagPath, "\(tagPath)/%", safeLimit, safeOffset]).map(Self.mapListItemRow)
            }
        }

        return try PerformanceSignpost.measure(.vaultListPage) {
            try Row.fetchAll(db, sql: """
                \(Self.listItemSelectSQL)
                FROM note n
                WHERE n.is_deleted = 0
                ORDER BY n.is_pinned DESC, n.updated_at DESC
                LIMIT ? OFFSET ?
            """, arguments: [safeLimit, safeOffset]).map(Self.mapListItemRow)
        }
    }

    func countNoteSummaries(tagPath: String?, in db: Database) throws -> Int {
        if let tagPath {
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(DISTINCT n.id)
                FROM note n
                JOIN note_tag nt ON nt.note_id = n.id
                JOIN tag t ON t.id = nt.tag_id
                WHERE n.is_deleted = 0
                  AND (t.path = ? OR t.path LIKE ?)
            """, arguments: [tagPath, "\(tagPath)/%"]) ?? 0
        }

        return try Int.fetchOne(db, sql: """
            SELECT COUNT(*)
            FROM note n
            WHERE n.is_deleted = 0
        """) ?? 0
    }

    func fetchAllNoteSummaries(in db: Database) throws -> [NoteListItem] {
        try fetchNoteSummariesFiltered(by: nil, in: db)
    }
}
