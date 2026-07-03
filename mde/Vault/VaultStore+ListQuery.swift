//
//  VaultStore+ListQuery.swift
//  MDE
//

import Foundation
import GRDB

extension VaultStore {
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
        if let tagPath {
            return try Row.fetchAll(db, sql: """
                \(Self.listItemSelectSQL)
                FROM note n
                JOIN note_tag nt ON nt.note_id = n.id
                JOIN tag t ON t.id = nt.tag_id
                WHERE n.is_deleted = 0
                  AND (t.path = ? OR t.path LIKE ?)
                GROUP BY n.id
                ORDER BY n.is_pinned DESC, n.updated_at DESC
            """, arguments: [tagPath, "\(tagPath)/%"]).map(Self.mapListItemRow)
        }

        return try Row.fetchAll(db, sql: """
            \(Self.listItemSelectSQL)
            FROM note n
            WHERE n.is_deleted = 0
            ORDER BY n.is_pinned DESC, n.updated_at DESC
        """).map(Self.mapListItemRow)
    }

    func fetchAllNoteSummaries(in db: Database) throws -> [NoteListItem] {
        try fetchNoteSummariesFiltered(by: nil, in: db)
    }
}
