//
//  VaultStore+Graph.swift
//  MDE
//

import Foundation
import GRDB

struct WikiGraphNode: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

struct WikiGraphEdge: Identifiable, Equatable, Sendable {
    let id: String
    let sourceID: String
    let targetID: String?
    let targetTitle: String
}

extension WikiGraphNode: FetchableRecord, Decodable {
    init(row: Row) {
        id = row["id"]
        title = row["title"]
    }
}
