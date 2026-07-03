//
//  Note.swift
//  MDE
//

import Foundation
import GRDB

struct Note: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    var rowid: Int64?
    var id: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var isPinned: Bool
    var isDeleted: Bool
    var version: Int
    var clientUpdatedAt: Date
    var checksum: String

    static let databaseTableName = "note"

    enum CodingKeys: String, CodingKey {
        case rowid, id, title, content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPinned = "is_pinned"
        case isDeleted = "is_deleted"
        case version
        case clientUpdatedAt = "client_updated_at"
        case checksum
    }

    enum Columns: String, ColumnExpression {
        case rowid, id, title, content
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case isPinned = "is_pinned"
        case isDeleted = "is_deleted"
        case version
        case clientUpdatedAt = "client_updated_at"
        case checksum
    }

    init(
        id: String = UUID().uuidString,
        title: String = "",
        content: String = "",
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        isPinned: Bool = false,
        isDeleted: Bool = false,
        version: Int = 1,
        clientUpdatedAt: Date = Date(),
        checksum: String = ""
    ) {
        self.id = id
        self.title = title
        self.content = content
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.isPinned = isPinned
        self.isDeleted = isDeleted
        self.version = version
        self.clientUpdatedAt = clientUpdatedAt
        self.checksum = checksum
    }

    mutating func didInsert(_ inserted: InsertionSuccess) {
        rowid = inserted.rowID
    }
}
