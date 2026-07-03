//
//  SyncChecksum.swift
//  MDE
//

import CryptoKit
import Foundation

enum SyncChecksum {
    static func compute(
        title: String,
        content: String,
        version: Int,
        isPinned: Bool,
        isDeleted: Bool
    ) -> String {
        let material = "\(title)|\(content)|\(version)|\(isPinned)|\(isDeleted)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func compute(for payload: NoteSyncPayload) -> String {
        compute(
            title: payload.title,
            content: payload.content,
            version: payload.version,
            isPinned: payload.isPinned,
            isDeleted: payload.isDeleted
        )
    }

    static func compute(for note: Note) -> String {
        compute(
            title: note.title,
            content: note.content,
            version: note.version,
            isPinned: note.isPinned,
            isDeleted: note.isDeleted
        )
    }
}
