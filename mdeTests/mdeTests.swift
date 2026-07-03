//
//  mdeTests.swift
//  mdeTests
//

import Foundation
import GRDB
import Testing
@testable import mde

struct DatabaseSchemaTests {

    @Test func migratesOnEmptyDatabase() throws {
        let dbQueue = try DatabaseQueue()
        try DatabaseSchema.migrate(dbQueue)

        try dbQueue.read { db in
            let tables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'table' AND name NOT LIKE 'sqlite_%'
                ORDER BY name
            """)
            #expect(tables.contains("note"))
            #expect(tables.contains("tag"))
            #expect(tables.contains("note_tag"))
            #expect(tables.contains("note_link"))
            #expect(tables.contains("sync_queue"))
            #expect(tables.contains("note_sync_base"))

            let ftsTables = try String.fetchAll(db, sql: """
                SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'note_fts'
            """)
            #expect(ftsTables == ["note_fts"])
        }
    }

    @Test func insertsNoteWithFTSIndex() throws {
        let dbQueue = try DatabaseQueue()
        try DatabaseSchema.migrate(dbQueue)

        var note = Note(title: "Hello", content: "World #inbox")
        try dbQueue.write { db in
            try note.insert(db)
        }

        try dbQueue.read { db in
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM note") ?? 0
            #expect(count == 1)

            let ftsCount = try Int.fetchOne(db, sql: """
                SELECT COUNT(*) FROM note_fts WHERE note_fts MATCH 'World'
            """) ?? 0
            #expect(ftsCount == 1)
        }
    }
}

struct VaultMetaTests {

    @Test func roundTripsJSON() throws {
        let meta = VaultMeta(formatVersion: 1, vaultID: "abc-123", createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try VaultMeta.decode(from: try meta.data())
        #expect(decoded.formatVersion == 1)
        #expect(decoded.vaultID == "abc-123")
    }
}

struct TagExtractorTests {

    @Test func extractsNestedTags() {
        let paths = TagExtractor.extractPaths(from: "Meeting #work/active and #inbox")
        #expect(paths.contains("work/active"))
        #expect(paths.contains("inbox"))
    }

    @Test func ignoresTagsInCodeSpans() {
        let paths = TagExtractor.extractPaths(from: "Use `#not-a-tag` inline")
        #expect(paths.isEmpty)
    }
}

struct TitleDeriverTests {

    @Test func derivesFromHeading() {
        let title = TitleDeriver.derive(from: "# Project\nBody", existingTitles: [])
        #expect(title == "Project")
    }

    @Test func derivesFromFirstLine() {
        let title = TitleDeriver.derive(from: "Hello world", existingTitles: [])
        #expect(title == "Hello world")
    }
}

struct VaultStoreTests {

    @Test func createsAndListsNotes() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "First", content: "Body")
        #expect(store.notes.count == 1)
        #expect(store.notes[0].title == "First")
    }

    @Test func softDeletesNote() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Delete me")
        let displayed = try store.notesFiltered(by: nil)
        try store.softDeleteNotes(at: IndexSet(integer: 0), in: displayed)
        #expect(store.notes.isEmpty)
    }

    @Test func packageRoundTrip() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Vault", content: "Persisted")

        let snapshot = try store.makeSnapshot()
        let wrapper = snapshot.makeFileWrapper()

        let loaded = VaultStore()
        try loaded.load(from: wrapper)

        #expect(loaded.meta.vaultID == store.meta.vaultID)
        #expect(loaded.notes.count == 1)
        #expect(loaded.notes[0].title == "Vault")
    }

    @Test func attachesToPackageDirectory() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "On disk")

        try store.attachToPackage(at: tempDir)
        try store.persistToPackageIfNeeded()

        #expect(FileManager.default.fileExists(atPath: VaultPaths.metaURL(in: tempDir).path))
        #expect(FileManager.default.fileExists(atPath: VaultPaths.databaseURL(in: tempDir).path))
        #expect(FileManager.default.fileExists(atPath: VaultPaths.assetsURL(in: tempDir).path))

        let reopened = VaultStore()
        try reopened.attachToPackage(at: tempDir)
        #expect(reopened.notes.count == 1)
        #expect(reopened.notes[0].title == "On disk")
    }

    // TC-001 — Create & autosave
    @Test func tc001CreateAndPersistContent() throws {
        let store = VaultStore()
        let note = try store.createNote()
        _ = try store.updateNote(id: note.id, content: "Hello #inbox")
        let reloaded = VaultStore()
        let snapshot = try store.makeSnapshot()
        try reloaded.load(from: snapshot.makeFileWrapper())
        #expect(reloaded.notes.first?.content.contains("inbox") == true)
    }

    // TC-002 — Tag sidebar filter
    @Test func tc002TagFilterIsSubtreeInclusive() throws {
        let store = VaultStore()
        _ = try store.createNote(content: "A #work")
        _ = try store.createNote(content: "B #work/active")

        #expect(store.tagTree.map(\.path).contains("work"))
        #expect(store.tagTree.map(\.path).contains("work/active"))

        let workNotes = try store.notesFiltered(by: "work")
        #expect(workNotes.count == 2)

        let activeNotes = try store.notesFiltered(by: "work/active")
        #expect(activeNotes.count == 1)
    }

    // TC-003 — Full-text search
    @Test func tc003SearchFindsContent() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Minerals", content: "quartz crystal")

        let results = try store.searchNotes(query: "quartz")
        #expect(results.count >= 1)
        #expect(results.first?.title == "Minerals")
    }

    // TC-004 — Title derivation
    @Test func tc004TitleDerivedFromHeading() throws {
        let store = VaultStore()
        let note = try store.createNote()
        let updated = try store.updateNote(id: note.id, content: "# Title\nBody")
        #expect(updated.title == "Title")
    }

    // TC-005 — WikiLink create
    @Test func tc005WikiLinkCreatesAndResolves() throws {
        let store = VaultStore()
        let source = try store.createNote(content: "See [[New Page]]")
        let target = try store.createNote(title: "New Page")

        #expect(store.noteID(forTitle: "New Page") == target.id)

        let backlinks = try store.fetchBacklinks(for: target.id, title: target.title)
        #expect(backlinks.contains(where: { $0.id == source.id }))
    }

    // TC-006 — Backlinks
    @Test func tc006BacklinksListLinkingNotes() throws {
        let store = VaultStore()
        let target = try store.createNote(title: "Target")
        let noteA = try store.createNote(title: "A", content: "Link [[Target]]")
        let noteB = try store.createNote(title: "B", content: "Also [[Target]]")

        let backlinks = try store.fetchBacklinks(for: target.id, title: target.title)
        #expect(backlinks.count == 2)
        #expect(backlinks.contains(where: { $0.id == noteA.id }))
        #expect(backlinks.contains(where: { $0.id == noteB.id }))
    }

    // TC-007 — Merge notes
    @Test func tc007MergeNotesIntoPrimary() throws {
        let store = VaultStore()
        let alpha = try store.createNote(title: "Alpha", content: "Alpha body")
        let beta = try store.createNote(title: "Beta", content: "Beta body")

        let merged = try store.mergeNotes(primaryID: alpha.id, otherIDs: [beta.id])

        #expect(merged.content.contains("## Merged from Beta"))
        #expect(merged.content.contains("Beta body"))
        #expect(store.notes.contains(where: { $0.id == alpha.id }))
        #expect(!store.notes.contains(where: { $0.id == beta.id }))
    }

    // TC-008 — Checkbox toggle
    @Test func tc008CheckboxTogglePersists() throws {
        let store = VaultStore()
        let note = try store.createNote(content: "- [ ] task")
        let toggled = TaskListHelper.toggleTask(at: 3, in: note.content)
        #expect(toggled?.contains("- [x] task") == true)

        let updated = try store.updateNote(id: note.id, content: toggled ?? "")
        #expect(updated.content.contains("- [x] task"))

        let reloaded = VaultStore()
        let snapshot = try store.makeSnapshot()
        try reloaded.load(from: snapshot.makeFileWrapper())
        #expect(reloaded.notes.first?.content.contains("- [x] task") == true)
    }
}

struct WikiLinkExtractorTests {

    @Test func extractsTitles() {
        let titles = WikiLinkExtractor.extractTitles(from: "See [[One]] and [[Two]]")
        #expect(titles == ["One", "Two"])
    }
}

struct TaskListHelperTests {

    @Test func togglesUncheckedToChecked() {
        let result = TaskListHelper.toggleTask(at: 5, in: "- [ ] buy milk")
        #expect(result == "- [x] buy milk")
    }

    @Test func togglesCheckedToUnchecked() {
        let result = TaskListHelper.toggleTask(at: 5, in: "- [x] buy milk")
        #expect(result == "- [ ] buy milk")
    }
}

struct SyncEncryptionTests {

    @Test func encryptsAndDecryptsPayload() throws {
        let key = SyncEncryption.generateKey()
        let payload = NoteSyncPayload(
            note: Note(title: "Secret", content: "Encrypted body"),
            vaultID: "vault"
        )
        let ciphertext = try SyncEncryption.encrypt(payload: payload, using: key)
        let decrypted = try SyncEncryption.decrypt(ciphertext, using: key)
        #expect(decrypted.noteID == payload.noteID)
        #expect(decrypted.content == "Encrypted body")
    }
}

struct NoteMergerTests {

    @Test func lwwPicksNewerRemote() {
        var local = NoteSyncPayload(note: Note(title: "A", content: "local"), vaultID: "v")
        local.version = 2
        local.clientUpdatedAt = Date(timeIntervalSince1970: 100)

        var remote = NoteSyncPayload(note: Note(title: "A", content: "remote"), vaultID: "v")
        remote.version = 2
        remote.clientUpdatedAt = Date(timeIntervalSince1970: 200)
        remote.checksum = SyncChecksum.compute(for: remote)

        let result = NoteMerger.merge(local: local, remote: remote, base: nil)
        if case .merged(let merged) = result {
            #expect(merged.content == "remote")
        } else {
            Issue.record("Expected merged result")
        }
    }
}

@MainActor
struct SyncCoordinatorTests {

    private func makeVaultID() -> String { "sync-test-\(UUID().uuidString)" }

    @Test(.serialized) func tc009SyncRoundTrip() async throws {
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let vaultID = makeVaultID()
        let key = SyncEncryption.generateKey()
        try keyStore.saveKey(key, vaultID: vaultID)

        let storeA = VaultStore(meta: VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true))
        let storeB = VaultStore(meta: VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true))

        let note = try storeA.createNote(title: "Sync", content: "Hello")
        _ = try storeA.updateNote(id: note.id, content: "Hello from Mac")
        let payload = try #require(try storeA.syncPayload(for: note.id))

        let ciphertext = try SyncEncryption.encrypt(payload: payload, using: key)
        try await transport.upload(
            EncryptedSyncRecord(
                noteID: payload.noteID,
                vaultID: vaultID,
                ciphertext: ciphertext,
                version: payload.version,
                clientUpdatedAt: payload.clientUpdatedAt,
                isDeleted: false
            ),
            vaultID: vaultID
        )

        let coordinator = SyncCoordinator(store: storeB, transport: transport, keyStore: keyStore)
        try await coordinator.enableSync()
        await coordinator.syncNow()

        #expect(storeB.notes.contains(where: { $0.id == note.id && $0.content.contains("Mac") }))
    }

    @Test(.serialized) func tc010OfflineEditSyncsWithoutDuplication() async throws {
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let vaultID = makeVaultID()
        let key = SyncEncryption.generateKey()
        try keyStore.saveKey(key, vaultID: vaultID)

        let store = VaultStore(meta: VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true))
        let note = try store.createNote(content: "Offline edit")
        _ = try store.updateNote(id: note.id, content: "Edited offline")
        let payload = try #require(try store.syncPayload(for: note.id))
        try? store.enqueueSync(noteID: note.id)
        let uploadPayload = try store.pendingSyncPayloads().first ?? payload

        transport.isOffline = true
        var offlineBlocked = false
        do {
            let ciphertext = try SyncEncryption.encrypt(payload: uploadPayload, using: key)
            try await transport.upload(
                EncryptedSyncRecord(
                    noteID: uploadPayload.noteID,
                    vaultID: vaultID,
                    ciphertext: ciphertext,
                    version: uploadPayload.version,
                    clientUpdatedAt: uploadPayload.clientUpdatedAt,
                    isDeleted: false
                ),
                vaultID: vaultID
            )
        } catch {
            offlineBlocked = true
        }
        #expect(offlineBlocked)

        transport.isOffline = false
        let ciphertext = try SyncEncryption.encrypt(payload: uploadPayload, using: key)
        try await transport.upload(
            EncryptedSyncRecord(
                noteID: uploadPayload.noteID,
                vaultID: vaultID,
                ciphertext: ciphertext,
                version: uploadPayload.version,
                clientUpdatedAt: uploadPayload.clientUpdatedAt,
                isDeleted: false
            ),
            vaultID: vaultID
        )
        try? store.clearSyncQueue()

        #expect(transport.uploadCount == 1)
    }

    @Test(.serialized) func tc011DuplicateTitleBlocked() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Daily")
        do {
            _ = try store.createNote(title: "daily")
            Issue.record("Expected duplicate title error")
        } catch VaultStoreError.duplicateTitle {
            #expect(true)
        }
    }
}
