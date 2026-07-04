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
        try fetchNoteSummariesPage(offset: 0, limit: Int.max, tagPath: tagPath, scope: .all, in: db)
    }

    func fetchNoteSummariesPage(
        offset: Int,
        limit: Int,
        tagPath: String?,
        scope: NoteListScope,
        sort: NoteListSort = .updated,
        in db: Database
    ) throws -> [NoteListItem] {
        let safeOffset = max(0, offset)
        let safeLimit = max(1, limit)
        let effectiveScope = effectiveListScope(tagPath: tagPath, scope: scope)
        let orderSQL = Self.listOrderSQL(sort: sort)

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
                    ORDER BY \(orderSQL)
                    LIMIT ? OFFSET ?
                """, arguments: [tagPath, "\(tagPath)/%", safeLimit, safeOffset]).map(Self.mapListItemRow)
            }
        }

        switch effectiveScope {
        case .trash:
            return try PerformanceSignpost.measure(.vaultListPage) {
                try Row.fetchAll(db, sql: """
                    \(Self.listItemSelectSQL)
                    FROM note n
                    WHERE n.is_deleted = 1
                    ORDER BY n.updated_at DESC
                    LIMIT ? OFFSET ?
                """, arguments: [safeLimit, safeOffset]).map(Self.mapListItemRow)
            }
        case .focused:
            let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -NoteListPolicy.recentDays,
                to: Date()
            ) ?? Date.distantPast
            return try PerformanceSignpost.measure(.vaultListPage) {
                try Row.fetchAll(db, sql: """
                    \(Self.listItemSelectSQL)
                    FROM note n
                    WHERE n.is_deleted = 0
                      AND (n.is_pinned = 1 OR n.updated_at >= ?)
                    ORDER BY \(orderSQL)
                    LIMIT ? OFFSET ?
                """, arguments: [cutoff, safeLimit, safeOffset]).map(Self.mapListItemRow)
            }
        case .all:
            return try PerformanceSignpost.measure(.vaultListPage) {
                try Row.fetchAll(db, sql: """
                    \(Self.listItemSelectSQL)
                    FROM note n
                    WHERE n.is_deleted = 0
                    ORDER BY \(orderSQL)
                    LIMIT ? OFFSET ?
                """, arguments: [safeLimit, safeOffset]).map(Self.mapListItemRow)
            }
        }
    }

    private static func listOrderSQL(sort: NoteListSort) -> String {
        switch sort {
        case .updated:
            "n.is_pinned DESC, n.updated_at DESC"
        case .title:
            "n.is_pinned DESC, lower(n.title) ASC, n.updated_at DESC"
        }
    }

    func countNoteSummaries(tagPath: String?, scope: NoteListScope, in db: Database) throws -> Int {
        let effectiveScope = effectiveListScope(tagPath: tagPath, scope: scope)

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

        switch effectiveScope {
        case .trash:
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE is_deleted = 1") ?? 0
        case .focused:
            let cutoff = Calendar.current.date(
                byAdding: .day,
                value: -NoteListPolicy.recentDays,
                to: Date()
            ) ?? Date.distantPast
            return try Int.fetchOne(db, sql: """
                SELECT COUNT(*)
                FROM note n
                WHERE n.is_deleted = 0
                  AND (n.is_pinned = 1 OR n.updated_at >= ?)
            """, arguments: [cutoff]) ?? 0
        case .all:
            return try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note WHERE is_deleted = 0") ?? 0
        }
    }

    func fetchAllNoteSummaries(in db: Database) throws -> [NoteListItem] {
        try fetchNoteSummariesFiltered(by: nil, in: db)
    }

    /// Tag filters always show the full subtree; trash is only available without a tag filter.
    func effectiveListScope(tagPath: String?, scope: NoteListScope) -> NoteListScope {
        if tagPath != nil { return .all }
        return scope
    }
}
