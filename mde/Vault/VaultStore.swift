//
//  VaultStore.swift
//  MDE
//

import Foundation
import GRDB
import Observation

enum VaultStoreError: LocalizedError {
    case duplicateTitle(String)
    case databaseUnavailable

    var errorDescription: String? {
        switch self {
        case .duplicateTitle(let title):
            return "A note titled \"\(title)\" already exists."
        case .databaseUnavailable:
            return "Vault database is not available."
        }
    }
}

@Observable
final class VaultStore {
    private(set) var meta: VaultMeta
    private var dbQueue: DatabaseQueue?
    private var packageURL: URL?

    var notes: [Note] = []
    var tagTree: [TagNode] = []

    var onNoteChanged: ((String) -> Void)?

    private var autosaveTask: Task<Void, Never>?

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

        try DatabaseSchema.migrate(dbQueue!, databaseURL: databaseURL)
        packageURL = url
        try refreshAll()
    }

    func load(from fileWrapper: FileWrapper) throws {
        let snapshot = try VaultFileSnapshot.load(from: fileWrapper)
        meta = snapshot.meta
        dbQueue = try Self.openDatabase(from: snapshot.databaseData)
        try DatabaseSchema.migrate(dbQueue!)
        packageURL = nil
        try refreshAll()
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
        if note.title.isEmpty {
            note.title = TitleDeriver.derive(from: content, existingTitles: try allTitles())
        }
        try validateUniqueTitle(note.title, excludingNoteID: nil)
        note.checksum = SyncChecksum.compute(for: note)

        try dbQueue.write { db in
            try note.insert(db)
            try NoteIndexer.reindexTags(for: note.id, content: note.content, in: db)
            try LinkIndexer.reindexLinks(for: note.id, content: note.content, in: db)
        }
        try refreshAll()
        noteChanged(note.id)
        return note
    }

    func updateNote(id: String, content: String) throws -> Note {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        var updated = try dbQueue.read { db in
            guard var note = try Note.filter(Note.Columns.id == id).fetchOne(db) else {
                throw VaultError.databaseUnavailable
            }
            return note
        }

        updated.content = content
        updated.updatedAt = Date()
        updated.clientUpdatedAt = Date()
        updated.version += 1

        let titles = try allTitles(excludingNoteID: id)
        updated.title = TitleDeriver.derive(from: content, existingTitles: titles, excludingNoteID: id)
        try validateUniqueTitle(updated.title, excludingNoteID: id)
        updated.checksum = SyncChecksum.compute(for: updated)

        try dbQueue.write { db in
            try updated.update(db)
            try NoteIndexer.reindexTags(for: id, content: content, in: db)
            try LinkIndexer.reindexLinks(for: id, content: content, in: db)
        }
        try refreshAll()
        noteChanged(id)
        return updated
    }

    func scheduleAutosave(noteID: String, content: String) {
        autosaveTask?.cancel()
        autosaveTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            do {
                _ = try updateNote(id: noteID, content: content)
                try persistToPackageIfNeeded()
            } catch {
                // Surface via UI on next explicit action
            }
        }
    }

    func softDeleteNotes(at offsets: IndexSet, in displayedNotes: [Note], notifySync: Bool = true) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        let ids = offsets.map { displayedNotes[$0].id }
        try dbQueue.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                    UPDATE note
                    SET is_deleted = 1, updated_at = ?, client_updated_at = ?, version = version + 1
                    WHERE id = ?
                    """,
                    arguments: [Date(), Date(), id]
                )
                if let note = try Note.filter(Note.Columns.id == id).fetchOne(db) {
                    var updated = note
                    updated.checksum = SyncChecksum.compute(for: updated)
                    try updated.update(db)
                }
            }
        }
        try refreshAll()
        if notifySync {
            ids.forEach { noteChanged($0) }
        }
    }

    func softDeleteNote(id: String, notifySync: Bool = true) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE note
                SET is_deleted = 1, updated_at = ?, client_updated_at = ?, version = version + 1
                WHERE id = ?
                """,
                arguments: [Date(), Date(), id]
            )
            if let note = try Note.filter(Note.Columns.id == id).fetchOne(db) {
                var updated = note
                updated.checksum = SyncChecksum.compute(for: updated)
                try updated.update(db)
            }
        }
        try refreshAll()
        if notifySync {
            noteChanged(id)
        }
    }

    func notesFiltered(by tagPath: String?) throws -> [Note] {
        guard let dbQueue else { return [] }

        if let tagPath {
            return try dbQueue.read { db in
                try Note.fetchAll(db, sql: """
                    SELECT DISTINCT n.*
                    FROM note n
                    JOIN note_tag nt ON nt.note_id = n.id
                    JOIN tag t ON t.id = nt.tag_id
                    WHERE n.is_deleted = 0
                      AND (t.path = ? OR t.path LIKE ?)
                    ORDER BY n.is_pinned DESC, n.updated_at DESC
                """, arguments: [tagPath, "\(tagPath)/%"])
            }
        }

        return try dbQueue.read { db in
            try Note
                .filter(Note.Columns.isDeleted == false)
                .order(Note.Columns.isPinned.desc, Note.Columns.updatedAt.desc)
                .fetchAll(db)
        }
    }

    func searchNotes(query: String) throws -> [SearchResult] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let dbQueue, !trimmed.isEmpty else { return [] }

        let ftsQuery = Self.ftsQuery(from: trimmed)
        return try dbQueue.read { db in
            let rows = try Row.fetchAll(db, sql: """
                SELECT n.id, n.title, n.updated_at,
                       snippet(note_fts, 1, '==', '==', '...', 12) AS match_snippet
                FROM note n
                JOIN note_fts ON note_fts.rowid = n.rowid
                WHERE note_fts MATCH ?
                  AND n.is_deleted = 0
                ORDER BY rank
                LIMIT 50
            """, arguments: [ftsQuery])

            return rows.map { row in
                SearchResult(
                    id: row["id"],
                    title: row["title"],
                    updatedAt: row["updated_at"],
                    snippet: row["match_snippet"] ?? ""
                )
            }
        }
    }

    func noteDisplayTitle(_ note: Note) -> String {
        let trimmed = note.title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        let content = note.content.trimmingCharacters(in: .whitespacesAndNewlines)
        if !content.isEmpty { return String(content.prefix(80)) }
        return "Untitled"
    }

    func noteSnippet(_ note: Note, maxLength: Int = 120) -> String {
        let text = note.content
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)) + "..."
    }

    func noteID(forTitle title: String) -> String? {
        let lowered = title.lowercased()
        return notes.first { $0.title.lowercased() == lowered }?.id
    }

    func resolvedWikiLinkTitles(in content: String) -> Set<String> {
        let existing = Set(notes.map { $0.title.lowercased() })
        return Set(
            WikiLinkExtractor.extractTitles(from: content)
                .filter { existing.contains($0.lowercased()) }
        )
    }

    func fetchBacklinks(for noteID: String, title: String) throws -> [Note] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            try LinkIndexer.fetchBacklinks(for: noteID, title: title, in: db)
        }
    }

    func togglePin(id: String) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            try db.execute(
                sql: """
                UPDATE note
                SET is_pinned = NOT is_pinned, updated_at = ?, client_updated_at = ?, version = version + 1
                WHERE id = ?
                """,
                arguments: [Date(), Date(), id]
            )
            if var note = try Note.filter(Note.Columns.id == id).fetchOne(db) {
                note.checksum = SyncChecksum.compute(for: note)
                try note.update(db)
            }
        }
        try refreshAll()
        noteChanged(id)
    }

    func mergeNotes(primaryID: String, otherIDs: [String]) throws -> Note {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        let uniqueOthers = otherIDs.filter { $0 != primaryID }

        var primary = try dbQueue.read { db in
            guard let note = try Note.filter(Note.Columns.id == primaryID).fetchOne(db) else {
                throw VaultError.databaseUnavailable
            }
            return note
        }

        let others = try dbQueue.read { db in
            try Note
                .filter(Note.Columns.isDeleted == false)
                .fetchAll(db)
                .filter { uniqueOthers.contains($0.id) }
        }

        for other in others {
            let section = "\n\n## Merged from \(other.title)\n\n\(other.content)"
            primary.content += section
        }

        primary.updatedAt = Date()
        primary.clientUpdatedAt = Date()
        primary.version += 1

        let titles = try allTitles(excludingNoteID: primaryID)
        primary.title = TitleDeriver.derive(from: primary.content, existingTitles: titles, excludingNoteID: primaryID)
        try validateUniqueTitle(primary.title, excludingNoteID: primaryID)
        primary.checksum = SyncChecksum.compute(for: primary)

        try dbQueue.write { db in
            try primary.update(db)
            try NoteIndexer.reindexTags(for: primaryID, content: primary.content, in: db)
            try LinkIndexer.reindexLinks(for: primaryID, content: primary.content, in: db)

            for other in others {
                try db.execute(
                    sql: """
                    UPDATE note
                    SET is_deleted = 1, updated_at = ?, client_updated_at = ?, version = version + 1
                    WHERE id = ?
                    """,
                    arguments: [Date(), Date(), other.id]
                )
                if var deleted = try Note.filter(Note.Columns.id == other.id).fetchOne(db) {
                    deleted.checksum = SyncChecksum.compute(for: deleted)
                    try deleted.update(db)
                }
            }
        }

        try refreshAll()
        noteChanged(primaryID)
        others.forEach { noteChanged($0.id) }
        return primary
    }

    // MARK: - Sync

    func setSyncEnabled(_ enabled: Bool) throws {
        meta.syncEnabled = enabled
        try persistToPackageIfNeeded()
    }

    func updateLastSyncedAt(_ date: Date) throws {
        meta.lastSyncedAt = date
        try persistToPackageIfNeeded()
    }

    func enqueueSync(noteID: String) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            try SyncQueueStore.enqueue(noteID: noteID, vaultID: meta.vaultID, in: db)
        }
    }

    func pendingSyncCount() throws -> Int {
        guard let dbQueue else { return 0 }
        return try dbQueue.read { db in
            try SyncQueueStore.pendingCount(vaultID: meta.vaultID, in: db)
        }
    }

    func pendingSyncPayloads() throws -> [NoteSyncPayload] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            let items = try SyncQueueItem
                .filter(SyncQueueItem.Columns.vaultID == meta.vaultID)
                .fetchAll(db)
            var payloads: [NoteSyncPayload] = []
            for item in items {
                guard let note = try Note.filter(Note.Columns.id == item.noteID).fetchOne(db) else {
                    continue
                }
                payloads.append(NoteSyncPayload(note: note, vaultID: meta.vaultID))
            }
            return payloads
        }
    }

    func clearSyncQueue() throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            _ = try SyncQueueStore.dequeueAll(vaultID: meta.vaultID, in: db)
        }
    }

    func syncPayload(for noteID: String) throws -> NoteSyncPayload? {
        guard let dbQueue else { return nil }
        return try dbQueue.read { db in
            guard let note = try Note.filter(Note.Columns.id == noteID).fetchOne(db) else {
                return nil
            }
            return NoteSyncPayload(note: note, vaultID: meta.vaultID)
        }
    }

    func syncBase(for noteID: String) throws -> NoteSyncPayload? {
        guard let dbQueue else { return nil }
        return try dbQueue.read { db in
            try SyncQueueStore.loadBase(noteID: noteID, in: db)
        }
    }

    func saveSyncBase(_ payload: NoteSyncPayload) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            try SyncQueueStore.saveBase(payload, in: db)
        }
    }

    func applySyncPayload(_ payload: NoteSyncPayload, notifySync: Bool = true) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        try dbQueue.write { db in
            if var existing = try Note.filter(Note.Columns.id == payload.noteID).fetchOne(db) {
                existing.title = payload.title
                existing.content = payload.content
                existing.updatedAt = payload.updatedAt
                existing.clientUpdatedAt = payload.clientUpdatedAt
                existing.isPinned = payload.isPinned
                existing.isDeleted = payload.isDeleted
                existing.version = payload.version
                existing.checksum = payload.checksum
                try existing.update(db)
                if !payload.isDeleted {
                    try NoteIndexer.reindexTags(for: existing.id, content: existing.content, in: db)
                    try LinkIndexer.reindexLinks(for: existing.id, content: existing.content, in: db)
                }
            } else if !payload.isDeleted {
                var note = Note(
                    id: payload.noteID,
                    title: payload.title,
                    content: payload.content,
                    createdAt: payload.createdAt,
                    updatedAt: payload.updatedAt,
                    isPinned: payload.isPinned,
                    isDeleted: false,
                    version: payload.version,
                    clientUpdatedAt: payload.clientUpdatedAt,
                    checksum: payload.checksum
                )
                try note.insert(db)
                try NoteIndexer.reindexTags(for: note.id, content: note.content, in: db)
                try LinkIndexer.reindexLinks(for: note.id, content: note.content, in: db)
            }
        }
        try refreshAll()
        if notifySync {
            noteChanged(payload.noteID)
        }
    }

    // MARK: - Performance / testing

    /// Inserts many notes directly for performance benchmarking without reloading in-memory caches.
    func seedPerformanceNotes(count: Int, matchIndex: Int, matchContent: String) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            for index in 0..<count {
                var note = Note(
                    title: "Note \(index)",
                    content: index == matchIndex ? matchContent : "Lorem ipsum \(index)"
                )
                try note.insert(db)
            }
        }
    }

    // MARK: - Private

    private func noteChanged(_ noteID: String) {
        if meta.syncEnabled {
            try? enqueueSync(noteID: noteID)
        }
        onNoteChanged?(noteID)
    }

    private func refreshAll() throws {
        try reloadNotes()
        try reloadTagTree()
        try resolvePendingLinks()
    }

    private func resolvePendingLinks() throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try LinkIndexer.resolvePendingLinks(in: db)
        }
    }

    private func reloadNotes() throws {
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

    private func reloadTagTree() throws {
        guard let dbQueue else {
            tagTree = []
            return
        }
        tagTree = try dbQueue.read { db in
            try NoteIndexer.fetchTagTree(in: db)
        }
    }

    private func allTitles(excludingNoteID: String? = nil) throws -> [String] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            let notes = try Note.filter(Note.Columns.isDeleted == false).fetchAll(db)
            return notes
                .filter { $0.id != excludingNoteID }
                .map(\.title)
        }
    }

    private func validateUniqueTitle(_ title: String, excludingNoteID: String?) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        let lowered = title.lowercased()
        let conflict = try dbQueue.read { db in
            try Note
                .filter(Note.Columns.isDeleted == false)
                .filter(sql: "LOWER(title) = ?", arguments: [lowered])
                .fetchAll(db)
                .contains { $0.id != excludingNoteID }
        }
        if conflict {
            throw VaultStoreError.duplicateTitle(title)
        }
    }

    private func openInMemoryDatabase() {
        do {
            dbQueue = try DatabaseQueue()
            try DatabaseSchema.migrate(dbQueue!)
            try refreshAll()
        } catch {
            notes = []
            tagTree = []
        }
    }

    private static func ftsQuery(from userInput: String) -> String {
        userInput
            .split(whereSeparator: \.isWhitespace)
            .map { token in
                let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
                return "\"\(escaped)\"*"
            }
            .joined(separator: " ")
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
