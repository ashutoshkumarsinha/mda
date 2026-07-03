//
//  VaultPaths.swift
//  MDE
//

import Foundation

enum VaultPaths {
    static let metaFileName = "meta.json"
    static let databaseFileName = "notes.db"
    static let assetsDirectoryName = "assets"
    static let formatVersion = 1

    static func metaURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(metaFileName, isDirectory: false)
    }

    static func databaseURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(databaseFileName, isDirectory: false)
    }

    static func assetsURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent(assetsDirectoryName, isDirectory: true)
    }

    static func backupDatabaseURL(in packageURL: URL) -> URL {
        packageURL.appendingPathComponent("notes.backup.db", isDirectory: false)
    }
}
