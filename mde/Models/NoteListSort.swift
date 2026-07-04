//
//  NoteListSort.swift
//  MDE
//

import Foundation

enum NoteListSort: String, CaseIterable, Identifiable, Sendable {
    case updated = "Recently Updated"
    case title = "Title"

    var id: String { rawValue }

    var systemImage: String {
        switch self {
        case .updated: "clock"
        case .title: "textformat.abc"
        }
    }
}
