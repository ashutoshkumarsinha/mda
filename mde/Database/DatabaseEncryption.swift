//
//  DatabaseEncryption.swift
//  MDE
//
//  OQ-02 — SQLCipher at-rest encryption for vault notes.db.
//

import Foundation
import GRDB

enum DatabaseEncryption {
    private static let sqliteHeader = "SQLite format 3"

    static func isPlaintextSQLiteFile(at url: URL) -> Bool {
        guard let header = try? Data(contentsOf: url, options: [.mappedIfSafe]).prefix(16),
              let text = String(data: header, encoding: .ascii) else {
            return false
        }
        return text.hasPrefix(sqliteHeader)
    }

    static func canOpenEncryptedDatabase(at url: URL, key: Data) -> Bool {
        guard let queue = try? DatabaseConfiguration.makeQueue(path: url.path, passphrase: key) else {
            return false
        }
        defer { try? queue.close() }
        return (try? queue.read { db in
            try String.fetchOne(db, sql: "PRAGMA integrity_check") == "ok"
        }) == true
    }

    static func validateQueue(_ queue: DatabaseQueue) throws {
        try queue.read { db in
            let result = try String.fetchOne(db, sql: "PRAGMA integrity_check") ?? "failed"
            guard result == "ok" else {
                throw VaultError.databaseCorrupt(backupAvailable: false)
            }
            let noteTable = try String.fetchOne(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'note'
            """)
            guard noteTable == "note" else {
                throw VaultError.databaseCorrupt(backupAvailable: false)
            }
        }
    }

    /// Opens an on-disk vault database, migrating legacy plaintext files when needed.
    static func openPackageDatabase(
        at databaseURL: URL,
        vaultID: String,
        keyStore: VaultDatabaseKeyStoring
    ) throws -> DatabaseQueue {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: databaseURL.path) else {
            let key = try keyStore.loadOrCreateKey(vaultID: vaultID)
            return try DatabaseConfiguration.makeQueue(path: databaseURL.path, passphrase: key)
        }

        let key = try keyStore.loadOrCreateKey(vaultID: vaultID)

        if canOpenEncryptedDatabase(at: databaseURL, key: key) {
            let queue = try DatabaseConfiguration.makeQueue(path: databaseURL.path, passphrase: key)
            try validateQueue(queue)
            return queue
        }

        guard isPlaintextSQLiteFile(at: databaseURL) else {
            throw VaultError.databaseCorrupt(backupAvailable: fileManager.fileExists(
                atPath: VaultPaths.backupDatabaseURL(in: databaseURL.deletingLastPathComponent()).path
            ))
        }

        return try migratePlaintextToEncrypted(at: databaseURL, key: key)
    }

  private static func migratePlaintextToEncrypted(at databaseURL: URL, key: Data) throws -> DatabaseQueue {
        let fileManager = FileManager.default
        let packageURL = databaseURL.deletingLastPathComponent()
        let backupURL = VaultPaths.backupDatabaseURL(in: packageURL)
        let encryptedTempURL = packageURL.appendingPathComponent("notes.encrypting.db")

        if fileManager.fileExists(atPath: encryptedTempURL.path) {
            try? fileManager.removeItem(at: encryptedTempURL)
        }

        let plaintextQueue = try DatabaseConfiguration.makeQueue(path: databaseURL.path)
        try validateQueue(plaintextQueue)

        try plaintextQueue.write { db in
            try db.execute(
                sql: "ATTACH DATABASE ? AS encrypted KEY ?",
                arguments: [encryptedTempURL.path, key]
            )
            try db.execute(sql: "SELECT sqlcipher_export('encrypted')")
            try db.execute(sql: "PRAGMA encrypted.journal_mode = DELETE")
        }
        try plaintextQueue.close()

        if fileManager.fileExists(atPath: backupURL.path) {
            try fileManager.removeItem(at: backupURL)
        }
        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.copyItem(at: databaseURL, to: backupURL)
            try fileManager.removeItem(at: databaseURL)
        }
        try fileManager.moveItem(at: encryptedTempURL, to: databaseURL)

        let encryptedQueue = try DatabaseConfiguration.makeQueue(path: databaseURL.path, passphrase: key)
        try validateQueue(encryptedQueue)
        return encryptedQueue
    }
}
