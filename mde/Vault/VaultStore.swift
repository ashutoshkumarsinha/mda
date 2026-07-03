//
//  VaultStore.swift
//  MDE
//

import Foundation
import GRDB
import Observation

@Observable
final class VaultStore {
    private(set) var meta: VaultMeta
    private var dbQueue: DatabaseQueue?
    private var packageURL: URL?

    var notes: [Note] = []

    init(meta: VaultMeta = .makeNew()) {
        self.meta = meta
        openInMemoryDatabase()
    }

    // MARK: - Package lifecycle

    func attachToPackage(at url: URL) throws {
        if packageURL == url, dbQueue != nil { return }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)

        let metaURL = VaultPaths.metaURL(in: url)
        let databaseURL = VaultPaths.databaseURL(in: url)
        let assetsURL = VaultPaths.assetsURL(in: url)

        if fileManager.fileExists(atPath: metaURL.path) {
            let data = try Data(contentsOf: metaURL)
            meta = try VaultMeta.decode(from: data)
        } else {
            try meta.data().write(to: metaURL, options: .atomic)
        }

        if !fileManager.fileExists(atPath: assetsURL.path) {
            try fileManager.createDirectory(at: assetsURL, withIntermediateDirectories: true)
        }

        if fileManager.fileExists(atPath: databaseURL.path) {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } else if let existing = dbQueue {
            let exported = try Self.exportDatabase(from: existing)
            try exported.write(to: databaseURL, options: .atomic)
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        } else {
            dbQueue = try DatabaseQueue(path: databaseURL.path)
        }

        try DatabaseSchema.migrate(dbQueue!)
        packageURL = url
        try reloadNotes()
    }

    func load(from fileWrapper: FileWrapper) throws {
        let snapshot = try VaultFileSnapshot.load(from: fileWrapper)
        meta = snapshot.meta
        dbQueue = try Self.openDatabase(from: snapshot.databaseData)
        try DatabaseSchema.migrate(dbQueue!)
        packageURL = nil
        try reloadNotes()
    }

    func makeSnapshot() throws -> VaultFileSnapshot {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        let databaseData = try Self.exportDatabase(from: dbQueue)
        return VaultFileSnapshot(meta: meta, databaseData: databaseData)
    }

    func persistToPackageIfNeeded() throws {
        guard let packageURL, let dbQueue else { return }

        try meta.data().write(to: VaultPaths.metaURL(in: packageURL), options: .atomic)

        let databaseURL = VaultPaths.databaseURL(in: packageURL)
        let exported = try Self.exportDatabase(from: dbQueue)
        try exported.write(to: databaseURL, options: .atomic)
    }

    // MARK: - Notes

    @discardableResult
    func createNote(title: String = "", content: String = "") throws -> Note {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        var note = Note(title: title, content: content)
        try dbQueue.write { db in
            try note.insert(db)
        }
        try reloadNotes()
        return note
    }

    func softDeleteNotes(at offsets: IndexSet) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        let ids = offsets.map { notes[$0].id }
        try dbQueue.write { db in
            for id in ids {
                try db.execute(
                    sql: "UPDATE note SET is_deleted = 1, updated_at = ? WHERE id = ?",
                    arguments: [Date(), id]
                )
            }
        }
        try reloadNotes()
    }

    func reloadNotes() throws {
        guard let dbQueue else {
            notes = []
            return
        }

        notes = try dbQueue.read { db in
            try Note
                .filter(Note.Columns.isDeleted == false)
                .order(Note.Columns.isPinned.desc, Note.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    // MARK: - Private

    private func openInMemoryDatabase() {
        do {
            dbQueue = try DatabaseQueue()
            try DatabaseSchema.migrate(dbQueue!)
            try reloadNotes()
        } catch {
            notes = []
        }
    }

    private static func openDatabase(from data: Data) throws -> DatabaseQueue {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        try data.write(to: tempURL, options: .atomic)
        return try DatabaseQueue(path: tempURL.path)
    }

    private static func exportDatabase(from source: DatabaseQueue) throws -> Data {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: url) }

        let destination = try DatabaseQueue(path: url.path)
        try source.backup(to: destination)
        try destination.close()
        return try Data(contentsOf: url)
    }
}
