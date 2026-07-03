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
}
