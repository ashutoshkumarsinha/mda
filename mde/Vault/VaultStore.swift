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

    let listState = VaultListState()
    let editorState = VaultEditorState()

    var noteSummaries: [NoteListItem] = []

    /// Bumps when list rows change (titles, pins, ordering).
    var listRevision: Int { listState.revision }
    /// Bumps when wiki-link graph may have changed.
    var linksRevision: Int { editorState.linksRevision }
    /// Bumps when a note body changes (editor reload from store).
    var contentEpoch: Int { editorState.contentEpoch }

    var tagTree: [TagNode] {
        get { listState.tagTree }
        set { listState.tagTree = newValue }
    }

    var onNoteChanged: ((String) -> Void)?

    private(set) var isPackageAttached = false
    var needsDatabaseRecovery = false

    var autosaveErrorMessage: String? {
        get { editorState.autosaveErrorMessage }
        set { editorState.autosaveErrorMessage = newValue }
    }

    private var autosaveTask: Task<Void, Never>?
    private var persistTask: Task<Void, Never>?
    private var periodicPersistTask: Task<Void, Never>?
    private var packageDirty = false
    private var titleIndex: [String: String] = [:]

    /// Test / legacy access — list metadata only; use `fetchNote(id:)` for body text.
    var notes: [Note] {
        noteSummaries.map {
            Note(
                id: $0.id,
                title: $0.title,
                content: "",
                updatedAt: $0.updatedAt,
                isPinned: $0.isPinned
            )
        }
    }

    init(meta: VaultMeta = .makeNew()) {
        self.meta = meta
        openInMemoryDatabase()
    }

    // MARK: - Package lifecycle

    func attachToPackage(at url: URL) throws {
        if packageURL == url, dbQueue != nil { return }

        let fileManager = FileManager.default
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        packageURL = url

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
            do {
                dbQueue = try Self.openValidatedDatabase(at: databaseURL)
            } catch {
                let backupURL = VaultPaths.backupDatabaseURL(in: url)
                if fileManager.fileExists(atPath: backupURL.path) {
                    needsDatabaseRecovery = true
                    throw VaultError.databaseCorrupt(backupAvailable: true)
                }
                throw error
            }
        } else if let existing = dbQueue {
            let exported = try Self.exportDatabase(from: existing)
            try exported.write(to: databaseURL, options: .atomic)
            dbQueue = try DatabaseConfiguration.makeQueue(path: databaseURL.path)
        } else {
            dbQueue = try DatabaseConfiguration.makeQueue(path: databaseURL.path)
        }

        try DatabaseSchema.migrate(dbQueue!, databaseURL: databaseURL)
        needsDatabaseRecovery = false
        isPackageAttached = true
        try refreshAll()
    }

    func restoreDatabaseFromBackup() throws {
        guard let packageURL else { throw VaultError.databaseUnavailable }

        let databaseURL = VaultPaths.databaseURL(in: packageURL)
        let backupURL = VaultPaths.backupDatabaseURL(in: packageURL)
        let fileManager = FileManager.default

        guard fileManager.fileExists(atPath: backupURL.path) else {
            throw VaultError.databaseCorrupt(backupAvailable: false)
        }

        if fileManager.fileExists(atPath: databaseURL.path) {
            try fileManager.removeItem(at: databaseURL)
        }
        try fileManager.copyItem(at: backupURL, to: databaseURL)

        dbQueue = try Self.openValidatedDatabase(at: databaseURL)
        try DatabaseSchema.migrate(dbQueue!, databaseURL: databaseURL)
        needsDatabaseRecovery = false
        autosaveErrorMessage = nil
        try refreshAll()
    }

    func load(from fileWrapper: FileWrapper) throws {
        let snapshot = try VaultFileSnapshot.load(from: fileWrapper)
        meta = snapshot.meta
        dbQueue = try Self.openDatabase(from: snapshot.databaseData)
        try DatabaseSchema.migrate(dbQueue!)
        packageURL = nil
        isPackageAttached = false
        try refreshAll()
    }

    func makeSnapshot() throws -> VaultFileSnapshot {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        let databaseData = try Self.exportDatabase(from: dbQueue)
        return VaultFileSnapshot(meta: meta, databaseData: databaseData)
    }

    func persistToPackageIfNeeded() throws {
        guard let packageURL, let dbQueue else { return }

        try PerformanceSignpost.measure(.vaultPersistPackage) {
            try meta.data().write(to: VaultPaths.metaURL(in: packageURL), options: .atomic)

            let databaseURL = VaultPaths.databaseURL(in: packageURL)
            let exported = try Self.exportDatabase(from: dbQueue)
            try exported.write(to: databaseURL, options: .atomic)
        }
        packageDirty = false
    }

    func flushPackageIfNeeded() throws {
        persistTask?.cancel()
        guard packageDirty else { return }
        try persistToPackageIfNeeded()
    }

    func markPackageDirty() {
        packageDirty = true
        schedulePersistToPackage()
    }

    func fetchNote(id: String) throws -> Note? {
        guard let dbQueue else { return nil }
        return try dbQueue.read { db in
            try Note.filter(Note.Columns.id == id).fetchOne(db)
        }
    }

    func noteSummary(id: String) -> NoteListItem? {
        noteSummaries.first { $0.id == id }
    }

    // MARK: - Notes

    @discardableResult
    func createNote(title: String = "", content: String = "") throws -> Note {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        var note = Note(title: title, content: content)
        if note.title.isEmpty {
            note.title = TitleDeriver.derive(from: content, existingTitles: titleStrings())
        }
        try validateUniqueTitle(note.title, excludingNoteID: nil)
        note.checksum = SyncChecksum.compute(for: note)

        try dbQueue.write { db in
            try note.insert(db)
            try NoteIndexer.reindexTags(for: note.id, content: note.content, in: db)
            try LinkIndexer.reindexLinks(for: note.id, content: note.content, in: db)
        }
        try applyNoteChanged(note, previousContent: nil)
        noteChanged(note.id)
        return note
    }

    func updateNote(id: String, content: String) throws -> Note {
        guard let dbQueue else { throw VaultError.databaseUnavailable }

        let previous = try fetchNote(id: id)

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

        updated.title = TitleDeriver.derive(
            from: content,
            existingTitles: titleStrings(excludingNoteID: id),
            excludingNoteID: id
        )
        try validateUniqueTitle(updated.title, excludingNoteID: id)
        updated.checksum = SyncChecksum.compute(for: updated)

        try dbQueue.write { db in
            try updated.update(db)
            try NoteIndexer.reindexTags(for: id, content: content, in: db)
            try LinkIndexer.reindexLinks(for: id, content: content, in: db)
        }
        try applyNoteChanged(updated, previousContent: previous?.content)
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
                markPackageDirty()
                autosaveErrorMessage = nil
            } catch {
                autosaveErrorMessage = error.localizedDescription
            }
        }
    }

    func saveNow(noteID: String, content: String) throws {
        autosaveTask?.cancel()
        do {
            _ = try updateNote(id: noteID, content: content)
            try flushPackageIfNeeded()
            autosaveErrorMessage = nil
        } catch {
            autosaveErrorMessage = error.localizedDescription
            throw error
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
        for id in ids {
            try removeNoteFromCaches(id: id)
        }
        try reloadTagTree()
        listState.bumpRevision()
        editorState.bumpLinksRevision()
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
        try removeNoteFromCaches(id: id)
        try reloadTagTree()
        listState.bumpRevision()
        editorState.bumpLinksRevision()
        if notifySync {
            noteChanged(id)
        }
    }

    func noteSummariesFiltered(by tagPath: String?) throws -> [NoteListItem] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            try fetchNoteSummariesFiltered(by: tagPath, in: db)
        }
    }

    func noteSummariesPage(offset: Int, limit: Int = listPageSize, tagPath: String?) throws -> [NoteListItem] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            try fetchNoteSummariesPage(offset: offset, limit: limit, tagPath: tagPath, in: db)
        }
    }

    func noteCountFiltered(by tagPath: String?) throws -> Int {
        guard let dbQueue else { return 0 }
        return try dbQueue.read { db in
            try countNoteSummaries(tagPath: tagPath, in: db)
        }
    }

    /// Legacy API — returns lightweight rows only (empty `content`).
    func notesFiltered(by tagPath: String?) throws -> [Note] {
        try noteSummariesFiltered(by: tagPath).map {
            Note(
                id: $0.id,
                title: $0.title,
                content: "",
                updatedAt: $0.updatedAt,
                isPinned: $0.isPinned
            )
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

    func noteDisplayTitle(_ item: NoteListItem) -> String {
        item.displayTitle()
    }

    func noteSnippet(_ note: Note, maxLength: Int = 120) -> String {
        if !note.content.isEmpty {
            return NoteListItem.makeSnippet(from: note.content, maxLength: maxLength)
        }
        if let item = noteSummary(id: note.id), !item.snippet.isEmpty {
            return item.snippet
        }
        return ""
    }

    func noteSnippet(_ item: NoteListItem, maxLength: Int = 120) -> String {
        guard !item.snippet.isEmpty else { return "" }
        if item.snippet.count <= maxLength { return item.snippet }
        return String(item.snippet.prefix(maxLength)) + "..."
    }

    func noteID(forTitle title: String) -> String? {
        titleIndex[title.lowercased()]
    }

    func resolvedWikiLinkTitles(in content: String) -> Set<String> {
        let existing = Set(titleIndex.keys)
        return Set(
            WikiLinkExtractor.extractTitles(from: content)
                .map { $0.lowercased() }
                .filter { existing.contains($0) }
        )
    }

    func fetchBacklinkSummaries(for noteID: String, title: String) throws -> [NoteListItem] {
        guard let dbQueue else { return [] }
        return try dbQueue.read { db in
            try Row.fetchAll(db, sql: """
                \(Self.listItemSelectSQL)
                FROM note n
                JOIN note_link nl ON nl.source_id = n.id
                WHERE (nl.target_id = ? OR LOWER(nl.target_title) = LOWER(?))
                  AND n.is_deleted = 0
                ORDER BY n.is_pinned DESC, n.updated_at DESC
            """, arguments: [noteID, title]).map(Self.mapListItemRow)
        }
    }

    func fetchBacklinks(for noteID: String, title: String) throws -> [Note] {
        try fetchBacklinkSummaries(for: noteID, title: title).map {
            Note(id: $0.id, title: $0.title, content: "", updatedAt: $0.updatedAt, isPinned: $0.isPinned)
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
        if let note = try fetchNote(id: id) {
            let snippet = NoteListItem.makeSnippet(from: note.content)
            insertSummarySorted(NoteListItem(note: note, snippet: snippet))
            listState.bumpRevision()
        }
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

        let titles = titleStrings(excludingNoteID: primaryID)
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
        listState.bumpRevision()
        editorState.bumpLinksRevision()
        noteChanged(primaryID)
        others.forEach { noteChanged($0.id) }
        return primary
    }

    // MARK: - Sync

    func setSyncEnabled(_ enabled: Bool) throws {
        meta.syncEnabled = enabled
        markPackageDirty()
    }

    func updateLastSyncedAt(_ date: Date) throws {
        meta.lastSyncedAt = date
        markPackageDirty()
    }

    func updateCloudChangeToken(_ token: Data?) throws {
        meta.cloudChangeToken = token
        markPackageDirty()
    }

    func dequeueSync(noteID: String) throws {
        guard let dbQueue else { throw VaultError.databaseUnavailable }
        try dbQueue.write { db in
            try SyncQueueStore.dequeue(noteID: noteID, vaultID: meta.vaultID, in: db)
        }
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
                .order(SyncQueueItem.Columns.enqueuedAt.asc)
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
        listState.bumpRevision()
        editorState.bumpLinksRevision()
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

    // MARK: - Performance measurement (Phase 0)

    func measureRefreshAll() throws -> Double {
        try PerformanceSignpost.elapsedMS { try refreshAll() }
    }

    func measureLoad1kNotesIntoCache() throws -> (refreshMS: Double, memoryDeltaMB: Double) {
        let memoryBefore = ProcessMemory.residentMegabytes()
        try seedPerformanceNotes(count: 1_000, matchIndex: -1, matchContent: "")
        let refreshMS = try measureRefreshAll()
        let memoryAfter = ProcessMemory.residentMegabytes()
        return (refreshMS, max(0, memoryAfter - memoryBefore))
    }

    func measureUpdateNote(id: String, content: String) throws -> Double {
        try PerformanceSignpost.elapsedMS {
            _ = try updateNote(id: id, content: content)
        }
    }

    func measurePersistToPackage() throws -> Double {
        packageDirty = true
        return try PerformanceSignpost.elapsedMS {
            try flushPackageIfNeeded()
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
        try PerformanceSignpost.measure(.vaultRefreshAll) {
            try PerformanceSignpost.measure(.vaultReloadNotes) { try reloadNotes() }
            try PerformanceSignpost.measure(.vaultReloadTagTree) { try reloadTagTree() }
            try PerformanceSignpost.measure(.vaultResolveLinks) { try resolvePendingLinks() }
        }
    }

    private func resolvePendingLinks() throws {
        guard let dbQueue else { return }
        try dbQueue.write { db in
            try LinkIndexer.resolvePendingLinks(in: db)
        }
    }

    private func reloadNotes() throws {
        guard let dbQueue else {
            noteSummaries = []
            return
        }

        noteSummaries = try dbQueue.read { db in
            try fetchAllNoteSummaries(in: db)
        }
        rebuildTitleIndex()
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

    private func titleStrings(excludingNoteID: String? = nil) -> [String] {
        noteSummaries
            .filter { $0.id != excludingNoteID }
            .map(\.title)
    }

    private func validateUniqueTitle(_ title: String, excludingNoteID: String?) throws {
        let lowered = title.lowercased()
        if let existingID = titleIndex[lowered], existingID != excludingNoteID {
            throw VaultStoreError.duplicateTitle(title)
        }
    }

    private func rebuildTitleIndex() {
        var index: [String: String] = [:]
        for item in noteSummaries {
            let lowered = item.title.lowercased()
            if !lowered.isEmpty {
                index[lowered] = item.id
            }
        }
        titleIndex = index
    }

    private func applyNoteChanged(_ note: Note, previousContent: String?) throws {
        let snippet = NoteListItem.makeSnippet(from: note.content)
        let item = NoteListItem(note: note, snippet: snippet)
        insertSummarySorted(item)
        rebuildTitleIndex()

        let oldTags = Set(TagExtractor.extractPaths(from: previousContent ?? ""))
        let newTags = Set(TagExtractor.extractPaths(from: note.content))
        if oldTags != newTags {
            try reloadTagTree()
        }

        let oldLinks = Set(WikiLinkExtractor.extractTitles(from: previousContent ?? ""))
        let newLinks = Set(WikiLinkExtractor.extractTitles(from: note.content))
        if oldLinks != newLinks {
            editorState.bumpLinksRevision()
        }

        editorState.bumpContentEpoch()
        listState.bumpRevision()
    }

    private func insertSummarySorted(_ item: NoteListItem) {
        noteSummaries.removeAll { $0.id == item.id }
        let insertIndex = noteSummaries.firstIndex { other in
            if item.isPinned != other.isPinned { return !item.isPinned && other.isPinned }
            return item.updatedAt < other.updatedAt
        } ?? noteSummaries.count
        noteSummaries.insert(item, at: insertIndex)
    }

    private func removeNoteFromCaches(id: String) throws {
        if let item = noteSummaries.first(where: { $0.id == id }) {
            let lowered = item.title.lowercased()
            if titleIndex[lowered] == id {
                titleIndex.removeValue(forKey: lowered)
            }
        }
        noteSummaries.removeAll { $0.id == id }
    }

    private static let packagePersistDebounce: Duration = .seconds(3)
    private static let packagePersistInterval: Duration = .seconds(300)

    private func schedulePersistToPackage() {
        persistTask?.cancel()
        persistTask = Task { @MainActor in
            try? await Task.sleep(for: Self.packagePersistDebounce)
            guard !Task.isCancelled, packageDirty else { return }
            try? persistToPackageIfNeeded()
        }
        ensurePeriodicPersistLoop()
    }

    private func ensurePeriodicPersistLoop() {
        guard periodicPersistTask == nil else { return }
        periodicPersistTask = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.packagePersistInterval)
                guard !Task.isCancelled, packageDirty else { continue }
                try? persistToPackageIfNeeded()
            }
        }
    }

    private func openInMemoryDatabase() {
        do {
            dbQueue = try DatabaseConfiguration.makeQueue()
            try DatabaseSchema.migrate(dbQueue!)
            try refreshAll()
        } catch {
            noteSummaries = []
            tagTree = []
            titleIndex = [:]
        }
    }

    private static func openValidatedDatabase(at url: URL) throws -> DatabaseQueue {
        let data = try Data(contentsOf: url)
        guard data.count >= 16,
              let header = String(data: data.prefix(16), encoding: .ascii),
              header.hasPrefix("SQLite format 3") else {
            throw VaultError.databaseCorrupt(backupAvailable: false)
        }

        let queue = try DatabaseConfiguration.makeQueue(path: url.path)
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
        return queue
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
        return try DatabaseConfiguration.makeQueue(path: tempURL.path)
    }

    private static func exportDatabase(from source: DatabaseQueue) throws -> Data {
        try PerformanceSignpost.measure(.vaultExportDatabase) {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension("db")
            defer { try? FileManager.default.removeItem(at: url) }

            let destination = try DatabaseConfiguration.makeQueue(path: url.path)
            try source.backup(to: destination)
            try destination.close()
            return try Data(contentsOf: url)
        }
    }
}
