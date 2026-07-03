//
//  NoteSyncPayload.swift
//  MDE
//

import Foundation

struct NoteSyncPayload: Codable, Equatable, Sendable {
    var noteID: String
    var vaultID: String
    var title: String
    var content: String
    var createdAt: Date
    var updatedAt: Date
    var clientUpdatedAt: Date
    var isPinned: Bool
    var isDeleted: Bool
    var version: Int
    var checksum: String

    init(note: Note, vaultID: String) {
        noteID = note.id
        self.vaultID = vaultID
        title = note.title
        content = note.content
        createdAt = note.createdAt
        updatedAt = note.updatedAt
        clientUpdatedAt = note.clientUpdatedAt
        isPinned = note.isPinned
        isDeleted = note.isDeleted
        version = note.version
        checksum = SyncChecksum.compute(for: note)
    }

    func refreshedChecksum() -> NoteSyncPayload {
        var copy = self
        copy.checksum = SyncChecksum.compute(for: copy)
        return copy
    }
}

struct NoteConflict: Equatable, Identifiable, Sendable {
    var id: String { noteID }
    var noteID: String
    var local: NoteSyncPayload
    var remote: NoteSyncPayload
    var base: NoteSyncPayload?
}

struct EncryptedSyncRecord: Equatable, Sendable {
    var noteID: String
    var vaultID: String
    var ciphertext: Data
    var version: Int
    var clientUpdatedAt: Date
    var isDeleted: Bool
}

struct SyncFetchResult: Sendable {
    var records: [EncryptedSyncRecord]
    var deletedNoteIDs: [String]
    var changeToken: Data?
}
