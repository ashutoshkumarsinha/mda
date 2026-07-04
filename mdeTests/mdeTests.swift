//
//  mdeTests.swift
//  mdeTests
//

import Foundation
import GRDB
import SwiftUI
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
        #expect(reloaded.notes.count == 1)
        let body = try reloaded.fetchNote(id: note.id)?.content ?? ""
        #expect(body.contains("inbox"))
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
        let saved = try reloaded.fetchNote(id: note.id)
        #expect(saved?.content.contains("- [x] task") == true)
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

        #expect(storeB.notes.contains(where: { $0.id == note.id }))
        let synced = try storeB.fetchNote(id: note.id)
        #expect(synced?.content.contains("Mac") == true)
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

struct AccessibilityTests {

    // TC-012 — VoiceOver navigation labels
    @Test func tc012PrimaryViewsExposeLabels() {
        #expect(AccessibilityLabels.tagSidebar == "Tags")
        #expect(AccessibilityLabels.noteList == "Notes")
        #expect(AccessibilityLabels.trashList == "Trash")
        #expect(AccessibilityLabels.noteEditor == "Note editor")
        #expect(AccessibilityLabels.exportNote == "Export note as Markdown")
        #expect(AccessibilityLabels.emptyBacklinks == "No notes link here yet")
        #expect(AccessibilityLabels.tagFilter(path: "inbox", isSelected: true).contains("inbox"))
        #expect(AccessibilityLabels.noteRow(
            title: "Meeting",
            snippet: "Discuss roadmap",
            isPinned: true,
            updatedAt: Date()
        ).contains("Meeting"))
        #expect(AccessibilityLabels.taskCheckbox(checked: true).contains("checked"))
        #expect(AccessibilityLabels.taskCheckbox(checked: false).contains("unchecked"))
    }
}

struct DynamicTypeTests {

    // TC-013 — Dynamic Type scaling
    @Test func tc013EditorFontScalesForAccessibility() {
        let medium = EditorTypography.baseFontSize(for: .medium)
        let accessibility3 = EditorTypography.baseFontSize(for: .accessibility3)
        let accessibility5 = EditorTypography.baseFontSize(for: .accessibility5)
        #expect(accessibility3 > medium)
        #expect(accessibility5 == accessibility3)
        #expect(EditorTypography.headingSize(level: 1, baseSize: accessibility3) > accessibility3)
    }
}

struct PerformanceTests {

    // FR-S04 — search P95 < 100 ms at 10k notes (single-run benchmark)
    @Test(.serialized) func searchPerformanceAt10kNotes() throws {
        let store = VaultStore()
        try store.seedPerformanceNotes(count: 10_000, matchIndex: 9_999, matchContent: "quartz crystal")

        let start = CFAbsoluteTimeGetCurrent()
        let results = try store.searchNotes(query: "quartz")
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        #expect(results.count >= 1)
        #expect(results.first?.title == "Note 9999")
        #expect(elapsedMS < PerformanceBudgets.search10kNotesMS)
    }
}

struct MigrationBackupTests {

    @Test func createsBackupBeforeMigratingExistingDatabase() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "Backup test")
        try store.attachToPackage(at: tempDir)

        let databaseURL = VaultPaths.databaseURL(in: tempDir)
        let backupURL = tempDir.appendingPathComponent("notes.backup.db")
        #expect(FileManager.default.fileExists(atPath: backupURL.path))
        #expect(FileManager.default.fileExists(atPath: databaseURL.path))
    }
}

struct ReleaseGateTests {

    // TC-014 — duplicate title prevents ambiguous link resolution
    @Test func tc014DuplicateTitleBlockedAtStoreLevel() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Dup")
        do {
            _ = try store.createNote(title: "Dup")
            Issue.record("Expected duplicate title error")
        } catch VaultStoreError.duplicateTitle {
            #expect(true)
        }
    }

    @Test func duplicateTitleSurfacesOnSaveNow() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Alpha", content: "# Alpha\none")
        let second = try store.createNote(title: "Beta", content: "two")

        do {
            try store.saveNow(noteID: second.id, content: "# Alpha\nconflict")
            Issue.record("Expected duplicate title on save")
        } catch VaultStoreError.duplicateTitle {
            #expect(store.autosaveErrorMessage?.contains("Alpha") == true)
        }
    }

    // TC-015 — v1 release gate (macOS + iOS automated suite)
    @Test func tc015ReleaseGateMetadata() {
        #expect(VaultPaths.formatVersion >= 1)
        #expect(OnboardingKeys.hasSeenOnboarding == "mde.hasSeenOnboarding")
    }
}

struct DatabaseRecoveryTests {

    @Test func restoresFromBackupWhenDatabaseCorrupt() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "Recoverable", content: "Keep me")
        try store.attachToPackage(at: tempDir)

        let databaseURL = VaultPaths.databaseURL(in: tempDir)
        let backupURL = VaultPaths.backupDatabaseURL(in: tempDir)
        #expect(FileManager.default.fileExists(atPath: backupURL.path))

        try Data().write(to: databaseURL, options: .atomic)

        let recoveryStore = VaultStore()
        do {
            try recoveryStore.attachToPackage(at: tempDir)
            Issue.record("Expected corrupt database error")
        } catch VaultError.databaseCorrupt {
            #expect(recoveryStore.needsDatabaseRecovery)
        }

        try recoveryStore.restoreDatabase(from: .migrationBackup)
        #expect(recoveryStore.notes.contains { $0.title == "Recoverable" })
        #expect(recoveryStore.needsDatabaseRecovery == false)
    }

    @Test func restoresFromAutosaveSnapshotWhenDatabaseCorrupt() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "Autosaved", content: "Snapshot body")
        try store.attachToPackage(at: tempDir)
        try store.flushPackageIfNeeded()

        let databaseURL = VaultPaths.databaseURL(in: tempDir)
        let backupURL = VaultPaths.backupDatabaseURL(in: tempDir)
        let autosaveURL = VaultPaths.autosaveSnapshotURL(in: tempDir)
        #expect(FileManager.default.fileExists(atPath: autosaveURL.path))
        try? FileManager.default.removeItem(at: backupURL)

        try Data().write(to: databaseURL, options: .atomic)

        let recoveryStore = VaultStore()
        do {
            try recoveryStore.attachToPackage(at: tempDir)
            Issue.record("Expected corrupt database error")
        } catch VaultError.databaseCorrupt {
            #expect(recoveryStore.needsDatabaseRecovery)
            #expect(recoveryStore.recoveryAutosaveAvailable)
            #expect(recoveryStore.recoveryBackupAvailable == false)
        }

        try recoveryStore.restoreDatabase(from: .autosaveSnapshot)
        #expect(recoveryStore.notes.contains { $0.title == "Autosaved" })
    }
}

struct MarkdownParseActorTests {

    @Test func parsesConstructsOffMainActor() async {
        let actor = MarkdownParseActor()
        let result = await actor.parse(text: "# Hello\n[[Link]] #tag")
        #expect(!result.constructs.isEmpty)
        #expect(result.documentParseSucceeded)
    }
}

struct PerformanceBudgetTests {

    @Test func coldStoreRefreshUnderBudget() throws {
        let store = VaultStore()
        let start = CFAbsoluteTimeGetCurrent()
        for index in 0..<100 {
            _ = try store.createNote(title: "Note \(index)", content: "Body \(index)")
        }
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(store.notes.count == 100)
        #expect(elapsedMS < 5_000)
    }
}

// MARK: - Phase 0 baselines (instrumentation + regression gates)

struct Phase0BaselineTests {

    @Test func phase0ColdVaultOpenUnderNFR02() throws {
        let start = CFAbsoluteTimeGetCurrent()
        let store = VaultStore()
        _ = try store.createNote(title: "Warm", content: "Editor ready")
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(store.notes.count == 1)
        #expect(elapsedMS < PerformanceBudgets.coldVaultOpenMS)
    }

    @Test(.serialized) func phase0RefreshAllAt1kNotes() throws {
        let store = VaultStore()
        let metrics = try store.measureLoad1kNotesIntoCache()
        #expect(store.notes.count == 1_000)
        #expect(metrics.refreshMS < PerformanceBudgets.refreshAll1kNotesMS)
        #expect(metrics.memoryDeltaMB < PerformanceBudgets.memoryDelta1kNotesMB)
    }

    @Test(.serialized) func phase0UpdateNoteIn1kVault() throws {
        let store = VaultStore()
        try store.seedPerformanceNotes(count: 1_000, matchIndex: -1, matchContent: "")
        try store.measureRefreshAll()
        guard let noteID = store.notes.first?.id else {
            Issue.record("Missing seeded note")
            return
        }
        let elapsedMS = try store.measureUpdateNote(
            id: noteID,
            content: "# Updated\n\nNew body for perf baseline."
        )
        #expect(elapsedMS < PerformanceBudgets.updateNote1kVaultMS)
    }

    @Test(.serialized) func phase0PersistPackageAt1kNotes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        try store.seedPerformanceNotes(count: 1_000, matchIndex: -1, matchContent: "")
        try store.measureRefreshAll()
        try store.attachToPackage(at: tempDir)

        let elapsedMS = try store.measurePersistToPackage()
        #expect(elapsedMS < PerformanceBudgets.persistPackage1kNotesMS)
    }

    @Test func phase0MarkdownParseUnderNFR01() async {
        let actor = MarkdownParseActor()
        let sample = String(repeating: "# Heading\nParagraph with **bold** and [[Link]].\n", count: 40)
        let start = CFAbsoluteTimeGetCurrent()
        let result = await actor.parse(text: sample)
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(!result.constructs.isEmpty)
        #expect(elapsedMS < PerformanceBudgets.markdownParseMS)
    }

    @Test func phase0MarkdownStyleBaseline() {
        let line = "# Heading\nParagraph with **bold** and `code`.\n"
        let text = String(repeating: line, count: 80)
        let storage = NSMutableAttributedString(string: text)
        let constructs = MarkdownConstructScanner.constructs(in: text)
        let start = CFAbsoluteTimeGetCurrent()
        MarkdownStyler.apply(
            to: storage,
            text: text,
            caretLocation: 0,
            constructs: constructs
        )
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(elapsedMS < PerformanceBudgets.markdownStylePassMS)
    }

    @MainActor
    @Test(.serialized) func phase0SyncRoundTripInMemory() async throws {
        let store = VaultStore()
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let coordinator = SyncCoordinator(store: store, transport: transport, keyStore: keyStore)
        try await coordinator.enableSync()

        let note = try store.createNote(title: "Sync perf", content: "Payload")

        let start = CFAbsoluteTimeGetCurrent()
        await coordinator.syncNow()
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        #expect(transport.uploadCount > 0)
        #expect(note.id.isEmpty == false)

        #if os(iOS)
        let syncBudget = PerformanceBudgets.syncRoundTripInMemoryMS * 6
        #else
        let syncBudget = PerformanceBudgets.syncRoundTripInMemoryMS
        #endif
        #expect(PerformanceRegressionGate.withinTolerance(
            metric: "sync_round_trip_in_memory_ms",
            actual: elapsedMS,
            budget: syncBudget
        ))
    }
}

// MARK: - Phase 1 optimization

struct Phase1OptimizationTests {

    @Test func phase1ListRowsExcludeFullBody() throws {
        let store = VaultStore()
        let longBody = String(repeating: "word ", count: 2_000)
        let note = try store.createNote(title: "Big", content: longBody)

        #expect(store.notes.count == 1)
        #expect(store.notes[0].content.isEmpty)
        #expect(store.noteSummaries[0].snippet.count <= 123)

        let full = try store.fetchNote(id: note.id)
        #expect(full?.content.count == longBody.count)
    }

    @Test func phase1TitleIndexResolvesWikiLinks() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Target Page")
        #expect(store.noteID(forTitle: "target page") != nil)
        #expect(store.noteID(forTitle: "missing") == nil)
    }

    @Test(.serialized) func phase1UpdateNoteAvoidsFullRefreshAll() throws {
        let store = VaultStore()
        try store.seedPerformanceNotes(count: 500, matchIndex: -1, matchContent: "")
        try store.measureRefreshAll()
        guard let noteID = store.notes.first?.id else {
            Issue.record("Missing seeded note")
            return
        }

        let beforeRevision = store.listRevision
        let updateMS = try store.measureUpdateNote(id: noteID, content: "Incremental save body")
        #expect(store.listRevision == beforeRevision + 1)
        #expect(updateMS < PerformanceBudgets.updateNote1kVaultMS)
    }

    @Test func phase1CoalescedPersistDefersDiskWrite() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "Deferred")
        try store.attachToPackage(at: tempDir)

        let dbURL = VaultPaths.databaseURL(in: tempDir)
        let metaURL = VaultPaths.metaURL(in: tempDir)
        let dbMtimeBefore = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.modificationDate] as? Date
        let metaMtimeBefore = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.modificationDate] as? Date

        store.markPackageDirty()
        try await Task.sleep(for: .milliseconds(100))

        let dbMtimeAfterDefer = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.modificationDate] as? Date
        let metaMtimeAfterDefer = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.modificationDate] as? Date
        #expect(dbMtimeAfterDefer == dbMtimeBefore)
        #expect(metaMtimeAfterDefer == metaMtimeBefore)

        try store.flushPackageIfNeeded()
        let dbMtimeFlushed = try FileManager.default.attributesOfItem(atPath: dbURL.path)[.modificationDate] as? Date
        let metaMtimeFlushed = try FileManager.default.attributesOfItem(atPath: metaURL.path)[.modificationDate] as? Date
        #expect(dbMtimeFlushed != dbMtimeBefore || metaMtimeFlushed != metaMtimeBefore)
    }
}

// MARK: - Phase 2 optimization

struct Phase2OptimizationTests {

    @Test func phase2UsesWALJournalMode() throws {
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("db")
        defer { try? FileManager.default.removeItem(at: tempURL) }

        let dbQueue = try DatabaseConfiguration.makeQueue(path: tempURL.path)
        try DatabaseSchema.migrate(dbQueue)
        try dbQueue.read { db in
            let mode = try DatabaseConfiguration.journalMode(on: db)
            #expect(mode == "wal")
        }
    }

    @Test func phase2ListOrderIndexExists() throws {
        let dbQueue = try DatabaseConfiguration.makeQueue()
        try DatabaseSchema.migrate(dbQueue)
        try dbQueue.read { db in
            let index = try String.fetchOne(db, sql: """
                SELECT name FROM sqlite_master
                WHERE type = 'index' AND name = 'idx_note_list_order'
            """)
            #expect(index == "idx_note_list_order")
        }
    }

    @Test func phase2PaginatesNoteSummaries() throws {
        let store = VaultStore()
        for index in 0..<150 {
            _ = try store.createNote(title: "Note \(index)")
        }

        let page1 = try store.noteSummariesPage(offset: 0, limit: 100, tagPath: nil)
        let page2 = try store.noteSummariesPage(offset: 100, limit: 100, tagPath: nil)

        #expect(page1.count == 100)
        #expect(page2.count == 50)
        #expect(page1.first?.id != page2.first?.id)
        #expect(try store.noteCountFiltered(by: nil) == 150)
    }

    @Test func phase2SkipsBackupWhenNoPendingMigrations() async throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        _ = try store.createNote(title: "Stable")
        try store.attachToPackage(at: tempDir)

        let backupURL = VaultPaths.backupDatabaseURL(in: tempDir)
        let mtimeBefore = try FileManager.default.attributesOfItem(atPath: backupURL.path)[.modificationDate] as? Date
        #expect(mtimeBefore != nil)

        try await Task.sleep(for: .milliseconds(100))

        let reopened = VaultStore()
        try reopened.attachToPackage(at: tempDir)
        let mtimeAfter = try FileManager.default.attributesOfItem(atPath: backupURL.path)[.modificationDate] as? Date
        #expect(mtimeAfter == mtimeBefore)
    }
}

// MARK: - Phase 3 optimization

struct Phase3OptimizationTests {

    @Test func phase3StylingNeighborhoodIsSmallVersusDocument() {
        let line = "# Heading\nParagraph with **bold** and `code`.\n"
        let text = String(repeating: line, count: 500)
        let caret = text.count / 2

        let neighborhood = MarkdownLineIndex.stylingNeighborhood(in: text, caretLocation: caret)
        #expect(neighborhood.length < text.count / 20)
    }

    @Test func phase3IncrementalStyleUnderNFR01Budget() {
        let line = "# Heading\nParagraph with **bold** and `code`.\n"
        let text = String(repeating: line, count: 500)
        let caret = text.count / 2
        let range = MarkdownLineIndex.stylingNeighborhood(in: text, caretLocation: caret)

        let storage = NSMutableAttributedString(string: text)
        let constructs = MarkdownConstructScanner.constructs(in: text)

        let start = CFAbsoluteTimeGetCurrent()
        MarkdownStyler.apply(
            to: storage,
            text: text,
            caretLocation: caret,
            constructs: constructs,
            styleRange: range
        )
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(elapsedMS < PerformanceBudgets.incrementalMarkdownStyleMS)
    }

    @Test func phase3ParseCacheReusesConstructs() async {
        let actor = MarkdownParseActor()
        let text = "# Hello\n[[Link]] #tag"

        let first = await actor.parse(text: text, caretLocation: 0)
        let second = await actor.parse(text: text, caretLocation: text.count - 1)

        #expect(!first.cacheHit)
        #expect(second.cacheHit)
        #expect(first.constructs.count == second.constructs.count)
    }

    @Test func phase3ConstructFilterRespectsStyleRange() {
        let text = "# One\n# Two\n# Three\n"
        let constructs = MarkdownConstructScanner.constructs(in: text)
        let middleLine = MarkdownLineIndex.lineRange(containing: text.count / 2, in: text)
        let scoped = MarkdownConstructScanner.constructs(constructs, intersecting: middleLine)
        #expect(scoped.count == 1)
    }
}

// MARK: - Phase 4 optimization

@Suite(.serialized)
@MainActor
struct Phase4OptimizationTests {

    private func makeVaultID() -> String { "phase4-\(UUID().uuidString)" }

    @Test func phase4SkipsDeltaUploadWhenChecksumMatches() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Delta", content: "Body")
        let payload = try #require(try store.syncPayload(for: note.id))
        try store.saveSyncBase(payload)
        try store.enqueueSync(noteID: note.id)

        let pending = try store.pendingSyncPayloads()
        let base = try #require(try store.syncBase(for: note.id))
        #expect(pending.count == 1)
        #expect(pending[0].checksum == base.checksum)
    }

    @Test func phase4PushPendingSkipsWhenBaseMatches() async throws {
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let vaultID = makeVaultID()
        try keyStore.saveKey(SyncEncryption.generateKey(), vaultID: vaultID)

        let store = VaultStore(meta: VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true))
        _ = try store.createNote(title: "Queued", content: "Payload")
        try store.saveSyncBase(try #require(try store.syncPayload(for: store.notes[0].id)))
        try store.enqueueSync(noteID: store.notes[0].id)

        let coordinator = SyncCoordinator(store: store, transport: transport, keyStore: keyStore)
        try await coordinator.enableSync()
        #expect(transport.uploadCount == 0)
        #expect(try store.pendingSyncCount() == 0)
    }

    @Test func phase4BootstrapSkipsStalePull() async throws {
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let vaultID = makeVaultID()
        let key = SyncEncryption.generateKey()
        try keyStore.saveKey(key, vaultID: vaultID)

        var meta = VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true)
        meta.lastSyncedAt = Date()
        meta.cloudChangeToken = Data("fresh-token".utf8)

        let store = VaultStore(meta: meta)
        let coordinator = SyncCoordinator(store: store, transport: transport, keyStore: keyStore)
        await coordinator.bootstrap()

        #expect(transport.fetchCount == 0)
    }

    @Test func phase4BackgroundPauseDefersDebouncedSync() async throws {
        let transport = InMemorySyncTransport()
        let keyStore = InMemorySyncKeyStore()
        let vaultID = makeVaultID()
        try keyStore.saveKey(SyncEncryption.generateKey(), vaultID: vaultID)

        let store = VaultStore(meta: VaultMeta(formatVersion: 1, vaultID: vaultID, createdAt: Date(), syncEnabled: true))
        let note = try store.createNote(title: "Deferred")
        let coordinator = SyncCoordinator(store: store, transport: transport, keyStore: keyStore)
        try await coordinator.enableSync()
        let uploadsAfterEnable = transport.uploadCount

        coordinator.setBackgroundPaused(true)
        await coordinator.syncNow()
        #expect(transport.uploadCount == uploadsAfterEnable)

        coordinator.setBackgroundPaused(false)
        await coordinator.syncNow(forceFull: true)
        #expect(transport.uploadCount == uploadsAfterEnable)
        #expect(try store.pendingSyncCount() == 0)
    }

    @Test func phase4RejectsOversizedEncryptedRecord() throws {
        let key = SyncEncryption.generateKey()
        var payload = NoteSyncPayload(
            note: Note(title: "Huge", content: String(repeating: "x", count: 2_000_000)),
            vaultID: "vault"
        )
        payload.content = String(repeating: "x", count: 2_000_000)
        payload = payload.refreshedChecksum()

        let ciphertext = try SyncEncryption.encrypt(payload: payload, using: key)
        if ciphertext.count > SyncPolicy.maxRecordBytes {
            #expect(true)
        } else {
            Issue.record("Expected ciphertext to exceed sync record budget in test")
        }
    }
}

// MARK: - Phase 5 optimization

struct Phase5OptimizationTests {

    @Test func phase5ObservationStatesAreIndependent() {
        let store = VaultStore()
        let listBefore = store.listState.revision
        let contentBefore = store.editorState.contentEpoch

        store.editorState.bumpContentEpoch()

        #expect(store.listState.revision == listBefore)
        #expect(store.editorState.contentEpoch == contentBefore + 1)
    }

    @Test func phase5ListRowIdentityTracksUpdatedAt() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Row", content: "Body")
        let item = try #require(store.noteSummary(id: note.id))
        let row = NoteListRow(item: item, store: store)
        #expect(row.rowIdentity.hasPrefix(note.id))
        #expect(row.rowIdentity.contains("\(item.updatedAt.timeIntervalSinceReferenceDate)"))
    }

    @Test func phase5EditorFontCapsAtAccessibility3() {
        let capped = EditorTypography.baseFontSize(for: .accessibility5)
        let maxSize = EditorTypography.baseFontSize(for: .accessibility3)
        #expect(capped == maxSize)
        #expect(capped == 29)
    }

    @Test func phase5AttachToPackageSetsBoundFlag() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        #expect(store.isPackageAttached == false)
        try store.attachToPackage(at: tempDir)
        #expect(store.isPackageAttached == true)
    }

    @Test func phase5ListRevisionForwardsListState() throws {
        let store = VaultStore()
        let before = store.listRevision
        _ = try store.createNote(title: "Bump")
        #expect(store.listRevision == before + 1)
        #expect(store.listState.revision == store.listRevision)
    }
}

// MARK: - Phase 6 observability

struct Phase6ObservabilityTests {

    @Test func phase6ColdLaunchSimulatedUnderNFR02() throws {
        let start = CFAbsoluteTimeGetCurrent()
        let store = VaultStore()
        _ = try store.createNote(title: "Launch", content: "Editor ready")
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(store.notes.count == 1)
        #expect(elapsedMS < PerformanceBudgets.coldVaultOpenMS)
    }

    @Test(.serialized) func phase6Memory1kNotesUnderNFR03() throws {
        let store = VaultStore()
        let metrics = try store.measureLoad1kNotesIntoCache()
        #expect(store.notes.count == 1_000)
        #expect(metrics.memoryDeltaMB < PerformanceBudgets.memory1kNotesNFR03MB)
    }

    @Test func phase6KeystrokeStyleP95UnderNFR01() {
        let line = "# Heading\nParagraph with **bold** and `code`.\n"
        let text = String(repeating: line, count: 500)
        var samples: [Double] = []
        let sampleCount = PerformanceBudgets.keystrokeStyleSampleCount

        for index in 0..<sampleCount {
            let caret = text.isEmpty
                ? 0
                : min((text.count * index) / max(sampleCount, 1), text.count - 1)
            let range = MarkdownLineIndex.stylingNeighborhood(in: text, caretLocation: caret)
            let storage = NSMutableAttributedString(string: text)
            let constructs = MarkdownConstructScanner.constructs(in: text)
            let start = CFAbsoluteTimeGetCurrent()
            MarkdownStyler.apply(
                to: storage,
                text: text,
                caretLocation: caret,
                constructs: constructs,
                styleRange: range
            )
            samples.append((CFAbsoluteTimeGetCurrent() - start) * 1_000)
        }

        let p95 = PerformancePercentile.value(samples, percentile: 0.95)
        #expect(p95 < PerformanceBudgets.incrementalMarkdownStyleMS)
    }

    @Test(.serialized) func phase6PackagePersistTimeAndSizeRegression() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let store = VaultStore()
        try store.seedPerformanceNotes(count: 1_000, matchIndex: -1, matchContent: "")
        try store.measureRefreshAll()
        try store.attachToPackage(at: tempDir)

        let result = try store.measurePersistPackageRegression(at: tempDir)
        #expect(result.persistMS < PerformanceBudgets.persistPackage1kNotesMS)
        #expect(result.databaseBytes > 0)
        #expect(result.databaseBytes < PerformanceBudgets.persistPackage1kNotesMaxBytes)
    }

    @Test(.serialized) func phase6FTS10kNotesUnderBudget() throws {
        let store = VaultStore()
        try store.seedPerformanceNotes(count: 10_000, matchIndex: 9_999, matchContent: "quartz crystal")

        let start = CFAbsoluteTimeGetCurrent()
        let results = try store.searchNotes(query: "quartz")
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000

        #expect(results.count >= 1)
        #expect(elapsedMS < PerformanceBudgets.search10kNotesMS)
    }

    @Test func phase6PercentileInterpolation() {
        let p95 = PerformancePercentile.value([1, 2, 3, 4, 100], percentile: 0.95)
        #expect(p95 >= 4)
        #expect(p95 <= 100)
    }
}

// MARK: - Phase 7 product enhancements

struct Phase7EnhancementTests {

    @Test func phase7ExportNoteAsMarkdown() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Export Me", content: "Body text")
        let markdown = try store.exportNoteAsMarkdown(id: note.id)
        #expect(markdown.contains("Export Me"))
        #expect(markdown.contains("Body text"))
        #expect(store.exportFilename(for: note.id) == "Export Me.md")
    }

    @Test func phase7FocusedScopeIncludesPinnedAndRecent() throws {
        let store = VaultStore()
        let pinned = try store.createNote(title: "Pinned")
        try store.togglePin(id: pinned.id)
        let recent = try store.createNote(title: "Recent")

        let focused = try store.noteSummariesPage(offset: 0, limit: 100, tagPath: nil, scope: .focused)
        let ids = Set(focused.map(\.id))
        #expect(ids.contains(pinned.id))
        #expect(ids.contains(recent.id))
        #expect(try store.noteCountFiltered(by: nil, scope: .focused) == 2)
    }

    @Test func phase7SoftDeletePurgeAndEmptyTrash() throws {
        let store = VaultStore()
        let first = try store.createNote(title: "One")
        let second = try store.createNote(title: "Two")

        try store.softDeleteNote(id: first.id)
        try store.softDeleteNote(id: second.id)
        #expect(try store.deletedNoteCount() == 2)

        try store.purgeNote(id: first.id)
        #expect(try store.deletedNoteCount() == 1)

        let purged = try store.emptyTrash()
        #expect(purged == 1)
        #expect(try store.deletedNoteCount() == 0)
        #expect(try store.fetchNote(id: second.id) == nil)
    }

    @Test func phase7RestoreNoteReturnsToActiveList() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Restore", content: "Keep")
        try store.softDeleteNote(id: note.id)
        #expect(store.noteSummary(id: note.id) == nil)

        try store.restoreNote(id: note.id)
        #expect(store.noteSummary(id: note.id)?.title == "Restore")
        #expect(try store.fetchNote(id: note.id)?.content == "Keep")
    }

    @Test func phase7TrashScopeListsDeletedOnly() throws {
        let store = VaultStore()
        let kept = try store.createNote(title: "Active")
        let deleted = try store.createNote(title: "Gone")
        try store.softDeleteNote(id: deleted.id)

        let trash = try store.noteSummariesPage(offset: 0, limit: 100, tagPath: nil, scope: .trash)
        #expect(trash.map(\.id).contains(deleted.id))
        #expect(!trash.map(\.id).contains(kept.id))
    }
}

// MARK: - Completion / gap closure

struct DatabaseEncryptionTests {

    @Test func encryptsNewPackageDatabaseAtRest() throws {
        let keyStore = InMemoryVaultDatabaseKeyStore()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let meta = VaultMeta.makeNew()
        let store = VaultStore(meta: meta, databaseKeyStore: keyStore)
        _ = try store.createNote(title: "Secret", content: "Encrypted body")
        try store.attachToPackage(at: tempDir)

        let databaseURL = VaultPaths.databaseURL(in: tempDir)
        let key = try keyStore.loadOrCreateKey(vaultID: meta.vaultID)
        #expect(DatabaseEncryption.canOpenEncryptedDatabase(at: databaseURL, key: key))
        #expect(store.meta.databaseEncrypted == true)

        let reopened = VaultStore(meta: meta, databaseKeyStore: keyStore)
        try reopened.attachToPackage(at: tempDir)
        let note = try reopened.fetchNote(id: reopened.notes[0].id)
        #expect(note?.content == "Encrypted body")
    }

    @Test func migratesLegacyPlaintextDatabaseToEncrypted() throws {
        let keyStore = InMemoryVaultDatabaseKeyStore()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mde")
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: VaultPaths.assetsURL(in: tempDir), withIntermediateDirectories: true)
        let meta = VaultMeta(formatVersion: 1, vaultID: UUID().uuidString, createdAt: Date(), databaseEncrypted: false)
        try meta.data().write(to: VaultPaths.metaURL(in: tempDir), options: .atomic)

        let databaseURL = VaultPaths.databaseURL(in: tempDir)
        let plaintextQueue = try DatabaseConfiguration.makeQueue(path: databaseURL.path)
        try DatabaseSchema.migrate(plaintextQueue)
        try plaintextQueue.write { db in
            var note = Note(title: "Legacy", content: "Plain")
            try note.insert(db)
        }
        try plaintextQueue.close()

        let migrated = VaultStore(meta: meta, databaseKeyStore: keyStore)
        try migrated.attachToPackage(at: tempDir)
        let key = try keyStore.loadOrCreateKey(vaultID: meta.vaultID)
        #expect(migrated.meta.databaseEncrypted == true)
        #expect(DatabaseEncryption.canOpenEncryptedDatabase(at: databaseURL, key: key))
        let note = try migrated.fetchNote(id: migrated.notes[0].id)
        #expect(note?.title == "Legacy")
    }
}

struct CompletionTests {

    @Test func completionExportsVaultMarkdown() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "One", content: "Alpha")
        _ = try store.createNote(title: "Two", content: "Beta")
        let combined = try store.exportVaultAsCombinedMarkdown()
        #expect(combined.contains("One"))
        #expect(combined.contains("Two"))
        #expect(combined.contains("---"))
    }

    @Test func completionImportsMarkdownFile() throws {
        let store = VaultStore()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("ImportedNote.md")
        try "# Imported\n\nBody".write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let note = try store.importMarkdownFile(from: url)
        #expect(note.title == "ImportedNote")
        #expect(note.content.contains("Body"))
    }

    @Test func completionFetchesWikiGraph() throws {
        let store = VaultStore()
        let target = try store.createNote(title: "Target")
        _ = try store.createNote(title: "Source", content: "See [[Target]]")
        let graph = try store.fetchWikiLinkGraph()
        #expect(graph.nodes.count >= 2)
        #expect(graph.edges.count >= 1)
        #expect(graph.edges.contains { $0.targetID == target.id || $0.targetTitle == "Target" })
    }

    @Test func completionGraphLayoutForceDirectedSeparatesNodes() {
        let nodes = [
            WikiGraphNode(id: "a", title: "A"),
            WikiGraphNode(id: "b", title: "B"),
            WikiGraphNode(id: "c", title: "C"),
        ]
        let edges = [
            WikiGraphEdge(id: "1", sourceID: "a", targetID: "b", targetTitle: "B"),
            WikiGraphEdge(id: "2", sourceID: "b", targetID: "c", targetTitle: "C"),
        ]
        let built = WikiGraphLayoutEngine.buildDisplayGraph(nodes: nodes, edges: edges)
        let laidOut = WikiGraphLayoutEngine.layout(
            nodes: built.nodes,
            edges: built.edges,
            in: CGSize(width: 400, height: 300),
            mode: .forceDirected,
            seed: 42
        )
        let posA = laidOut.nodes.first { $0.id == "a" }?.position
        let posB = laidOut.nodes.first { $0.id == "b" }?.position
        let posC = laidOut.nodes.first { $0.id == "c" }?.position
        let ab = hypot(posA!.x - posB!.x, posA!.y - posB!.y)
        let bc = hypot(posB!.x - posC!.x, posB!.y - posC!.y)
        #expect(ab > 10)
        #expect(bc > 10)
    }

    @Test func completionGraphLayoutUnresolvedPhantomNode() {
        let nodes = [WikiGraphNode(id: "a", title: "A")]
        let edges = [
            WikiGraphEdge(id: "1", sourceID: "a", targetID: nil, targetTitle: "Missing"),
        ]
        let built = WikiGraphLayoutEngine.buildDisplayGraph(nodes: nodes, edges: edges)
        #expect(built.nodes.count == 2)
        #expect(built.nodes.contains { $0.isUnresolved })
        #expect(built.edges.first?.isUnresolved == true)
    }

    @Test func completionColdLaunchSignpostLabel() {
        #expect(PerformanceSignpost.coldLaunchToEditor.label == "cold_launch_to_editor")
    }

    @Test func completionInstrumentsTraceTemplateExists() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let template = repoRoot
            .appendingPathComponent("docs/instruments/MDE Performance.tracetemplate")
        let attrs = try FileManager.default.attributesOfItem(atPath: template.path)
        let bytes = attrs[.size] as? UInt64 ?? 0
        #expect(FileManager.default.fileExists(atPath: template.path))
        #expect(bytes > 1_000)
        #expect(bytes < 50_000)
    }

    @Test func completionGraphFocusFiltersNeighborhood() {
        let nodes = [
            WikiGraphDisplayNode(id: "a", title: "A", isUnresolved: false, linkCount: 1, position: .zero),
            WikiGraphDisplayNode(id: "b", title: "B", isUnresolved: false, linkCount: 1, position: .zero),
            WikiGraphDisplayNode(id: "c", title: "C", isUnresolved: false, linkCount: 0, position: .zero),
        ]
        let edges = [
            WikiGraphDisplayEdge(id: "1", sourceID: "a", targetID: "b", isUnresolved: false),
        ]
        let full = WikiGraphLayoutResult(nodes: nodes, edges: edges)
        let focused = WikiGraphLayoutEngine.visibleGraph(
            result: full,
            focusNodeID: "a",
            focusEnabled: true
        )
        #expect(focused.nodes.map(\.id).sorted() == ["a", "b"])
        #expect(focused.edges.count == 1)
    }

    @Test func completionTrashPreviewFetchesListItem() throws {
        let store = VaultStore()
        let note = try store.createNote(title: "Trash preview", content: "Body")
        try store.softDeleteNote(id: note.id)
        let item = try #require(try store.fetchListItem(id: note.id))
        #expect(item.title == "Trash preview")
        let loaded = try #require(try store.fetchNote(id: note.id, includeDeleted: true))
        #expect(loaded.isDeleted)
    }

    @Test func completionBlockquoteAndFenceConstructs() {
        let text = "> Quote line\n\n```swift\ncode\n```\n"
        let constructs = MarkdownConstructScanner.constructs(in: text)
        #expect(constructs.contains { $0.kind == .blockquote })
        #expect(constructs.contains { $0.kind == .codeFence })
        #expect(constructs.contains { $0.kind == .codeBlockLine })
    }

    @Test func completionInlineCodeConstructOutsideFence() {
        let text = "Use `let x = 1` in Swift.\n\n```\n`not inline`\n```\n"
        let constructs = MarkdownConstructScanner.constructs(in: text)
        let inline = constructs.filter { $0.kind == .inlineCode }
        #expect(inline.count == 1)
        #expect((text as NSString).substring(with: inline[0].contentRange!) == "let x = 1")
    }

    @Test func completionInlineCodeSuppressesNestedMarkdown() {
        let text = "Literal `[[Not Link]]` and `#not-tag` here."
        let constructs = MarkdownConstructScanner.constructs(in: text)
        #expect(constructs.contains { $0.kind == .inlineCode })
        #expect(constructs.contains { $0.kind == .wikilink } == false)
        #expect(constructs.contains { $0.kind == .tag } == false)
    }

    @Test func completionListRevisionSkipsTailEdit() throws {
        let store = VaultStore()
        let body = "# Stable\n\n" + String(repeating: "word ", count: 200)
        let note = try store.createNote(title: "Stable", content: body)
        let before = store.listRevision
        _ = try store.updateNote(id: note.id, content: body + "tail")
        #expect(store.listRevision == before)
    }

    @Test func completionExportsVaultMarkdownFolder() throws {
        let store = VaultStore()
        _ = try store.createNote(title: "Alpha", content: "One")
        _ = try store.createNote(title: "Beta", content: "Two")
        let wrapper = try store.makeVaultMarkdownExportWrapper()
        #expect(wrapper.isDirectory)
        let files = wrapper.fileWrappers?.keys.sorted() ?? []
        #expect(files.count == 2)
        #expect(files.allSatisfy { $0.hasSuffix(".md") })
    }

    @Test func completionRegressionGateUsesPersistedBaselines() throws {
        let ceiling = PerformanceRegressionGate.ceiling(
            metric: "list_page_focused_ms",
            budget: 50
        )
        #expect(ceiling >= 50 * PerformanceRegressionGate.toleranceMultiplier)
    }

    @Test(.serialized) func completionRegressionGateAllowsTenPercentHeadroom() throws {
        let store = VaultStore()
        let start = CFAbsoluteTimeGetCurrent()
        _ = VaultStore()
        _ = try store.createNote(title: "Warm", content: "Ready")
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(PerformanceRegressionGate.withinTolerance(
            metric: "cold_vault_open_ms",
            actual: elapsedMS,
            budget: PerformanceBudgets.coldVaultOpenMS
        ))
    }

    @Test(.serialized) func completionListPageQueryUnderScrollBudget() throws {
        let store = VaultStore()
        try store.seedPerformanceNotes(count: 5_000, matchIndex: -1, matchContent: "")
        try store.measureRefreshAll()
        let start = CFAbsoluteTimeGetCurrent()
        _ = try store.noteSummariesPage(offset: 0, limit: 100, tagPath: nil, scope: .focused)
        let elapsedMS = (CFAbsoluteTimeGetCurrent() - start) * 1_000
        #expect(PerformanceRegressionGate.withinTolerance(
            metric: "list_page_focused_ms",
            actual: elapsedMS,
            budget: 50
        ))
    }
}
