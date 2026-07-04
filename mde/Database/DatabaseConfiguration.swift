//
//  DatabaseConfiguration.swift
//  MDE
//

import Foundation
import GRDB

enum DatabaseConfiguration {
    /// Negative `cache_size` = KiB pages in SQLite (8000 ≈ 8 MB).
    static let cacheSizeKiB = -8_000
    /// Memory-mapped I/O budget for large vaults (256 MB).
    static let mmapSizeBytes: Int64 = 256 * 1_024 * 1_024

    static func makeConfiguration(passphrase: Data? = nil) -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            if let passphrase {
                try db.usePassphrase(passphrase)
            }
            try applyPragmas(on: db)
        }
        return config
    }

    static func makeQueue(path: String? = nil, passphrase: Data? = nil) throws -> DatabaseQueue {
        let config = makeConfiguration(passphrase: passphrase)
        if let path {
            return try DatabaseQueue(path: path, configuration: config)
        }
        return try DatabaseQueue(configuration: config)
    }

    static func applyPragmas(on db: Database) throws {
        try db.execute(sql: "PRAGMA journal_mode = WAL")
        try db.execute(sql: "PRAGMA synchronous = NORMAL")
        try db.execute(sql: "PRAGMA cache_size = \(cacheSizeKiB)")
        try db.execute(sql: "PRAGMA mmap_size = \(mmapSizeBytes)")
        try db.execute(sql: "PRAGMA temp_store = MEMORY")
        try db.execute(sql: "PRAGMA cipher_memory_security = ON")
    }

    static func journalMode(on db: Database) throws -> String {
        let value = try String.fetchOne(db, sql: "PRAGMA journal_mode") ?? ""
        return value.lowercased()
    }
}
