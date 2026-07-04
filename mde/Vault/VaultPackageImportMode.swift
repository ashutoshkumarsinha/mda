//
//  VaultPackageImportMode.swift
//  MDE
//

import Foundation

enum VaultPackageImportMode: String, CaseIterable, Identifiable, Sendable {
    case add
    case merge
    case replace

    var id: String { rawValue }

    var label: String {
        switch self {
        case .add: "Add as new notes"
        case .merge: "Merge by note ID"
        case .replace: "Replace vault contents"
        }
    }

    var detail: String {
        switch self {
        case .add:
            "Create new notes and ignore export IDs."
        case .merge:
            "Update existing notes when IDs match; create missing ones with preserved IDs."
        case .replace:
            "Move current notes to Trash, then import the export with preserved IDs."
        }
    }

    var requiresConfirmation: Bool {
        self == .replace
    }
}

struct VaultPackageImportResult: Sendable {
    var notes: [Note]
    var assetsSkipped: Bool
}
