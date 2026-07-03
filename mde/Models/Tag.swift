//
//  Tag.swift
//  MDE
//

import Foundation
import GRDB

struct Tag: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var path: String
    var parentID: String?

    static let databaseTableName = "tag"

    enum CodingKeys: String, CodingKey {
        case id, name, path
        case parentID = "parent_id"
    }

    enum Columns: String, ColumnExpression {
        case id, name, path
        case parentID = "parent_id"
    }
}

struct TagNode: Identifiable, Equatable, Sendable {
    var id: String
    var name: String
    var path: String
    var level: Int
}

struct SearchResult: Identifiable, Equatable, Sendable {
    var id: String
    var title: String
    var updatedAt: Date
    var snippet: String
}
