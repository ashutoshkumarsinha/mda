//
//  NoteIndexer.swift
//  MDE
//

import Foundation
import GRDB

enum NoteIndexer {
    static func reindexTags(for noteID: String, content: String, in db: Database) throws {
        let paths = TagExtractor.extractPaths(from: content)

        try db.execute(sql: "DELETE FROM note_tag WHERE note_id = ?", arguments: [noteID])

        for path in paths {
            let tagID = try upsertTagHierarchy(path: path, in: db)
            try db.execute(
                sql: "INSERT OR IGNORE INTO note_tag (note_id, tag_id) VALUES (?, ?)",
                arguments: [noteID, tagID]
            )
        }
    }

    @discardableResult
    private static func upsertTagHierarchy(path: String, in db: Database) throws -> String {
        let segments = path.split(separator: "/").map(String.init)
        var parentID: String?
        var builtPath = ""

        for segment in segments {
            builtPath = builtPath.isEmpty ? segment : "\(builtPath)/\(segment)"
            let tagID = builtPath

            if try Tag.fetchOne(db, key: tagID) == nil {
                var tag = Tag(id: tagID, name: segment, path: builtPath, parentID: parentID)
                try tag.insert(db)
            }
            parentID = tagID
        }

        return path
    }

    static func fetchTagTree(in db: Database) throws -> [TagNode] {
        try Row.fetchAll(db, sql: """
            WITH RECURSIVE tag_tree(id, name, path, parent_id, level) AS (
                SELECT id, name, path, parent_id, 0 AS level
                FROM tag
                WHERE parent_id IS NULL
                UNION ALL
                SELECT t.id, t.name, t.path, t.parent_id, tt.level + 1
                FROM tag t
                JOIN tag_tree tt ON t.parent_id = tt.id
            )
            SELECT tt.id, tt.name, tt.path, tt.level
            FROM tag_tree tt
            WHERE EXISTS (
                SELECT 1
                FROM note_tag nt
                JOIN note n ON n.id = nt.note_id
                WHERE nt.tag_id = tt.id AND n.is_deleted = 0
            )
            ORDER BY tt.path ASC
        """).map { row in
            TagNode(
                id: row["id"],
                name: row["name"],
                path: row["path"],
                level: row["level"]
            )
        }
    }
}
