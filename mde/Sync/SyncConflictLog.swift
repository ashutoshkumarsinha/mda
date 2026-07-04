//
//  SyncConflictLog.swift
//  MDE
//

import Foundation

struct SyncConflictLogEntry: Codable, Identifiable, Equatable, Sendable {
    var id: UUID
    var noteID: String
    var noteTitle: String
    var recordedAt: Date

    init(noteID: String, noteTitle: String, recordedAt: Date = Date()) {
        self.id = UUID()
        self.noteID = noteID
        self.noteTitle = noteTitle
        self.recordedAt = recordedAt
    }
}

enum SyncConflictLog {
    private static let maxEntries = 10
    private static let storageKey = "mde.syncConflictLog"

    static func append(noteID: String, title: String, vaultID: String) {
        var all = loadAll()
        var entries = all[vaultID] ?? []
        entries.insert(SyncConflictLogEntry(noteID: noteID, noteTitle: title), at: 0)
        if entries.count > maxEntries {
            entries = Array(entries.prefix(maxEntries))
        }
        all[vaultID] = entries
        saveAll(all)
    }

    static func entries(vaultID: String) -> [SyncConflictLogEntry] {
        loadAll()[vaultID] ?? []
    }

    private static func loadAll() -> [String: [SyncConflictLogEntry]] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: [SyncConflictLogEntry]].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveAll(_ all: [String: [SyncConflictLogEntry]]) {
        guard let data = try? JSONEncoder().encode(all) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }
}
