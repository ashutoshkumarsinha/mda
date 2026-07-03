//
//  SyncCoordinator.swift
//  MDE
//

import CryptoKit
import Foundation
import Observation

enum SyncStatus: Equatable {
    case disabled
    case idle
    case syncing
    case offline
    case error(String)
}

@Observable
@MainActor
final class SyncCoordinator {
    private(set) var status: SyncStatus = .disabled
    private(set) var pendingUploadCount = 0
    var conflict: NoteConflict?
    var isSyncEnabled = false

    private let store: VaultStore
    private let transport: SyncTransport
    private let keyStore: SyncKeyStoring
    private var encryptionKey: SymmetricKey?
    private var changeToken: Data?
    private var syncTask: Task<Void, Never>?
    private var forceOffline = false

    init(
        store: VaultStore,
        transport: SyncTransport? = nil,
        keyStore: SyncKeyStoring = KeychainSyncKeyStore()
    ) {
        self.store = store
        self.transport = transport ?? CloudKitSyncTransport()
        self.keyStore = keyStore
        self.isSyncEnabled = store.meta.syncEnabled
        self.status = store.meta.syncEnabled ? .idle : .disabled
        store.onNoteChanged = { [weak self] noteID in
            self?.noteDidChange(noteID: noteID)
        }
    }

    func bootstrap() async {
        guard isSyncEnabled else { return }
        encryptionKey = try? keyStore.loadKey(vaultID: store.meta.vaultID)
        await refreshPendingCount()
        await syncNow()
    }

    func enableSync() async throws {
        let vaultID = store.meta.vaultID
        if let existing = try keyStore.loadKey(vaultID: vaultID) {
            encryptionKey = existing
        } else {
            let key = SyncEncryption.generateKey()
            try keyStore.saveKey(key, vaultID: vaultID)
            encryptionKey = key
        }

        try store.setSyncEnabled(true)
        isSyncEnabled = true
        status = .idle
        await syncNow()
    }

    func disableSync() {
        isSyncEnabled = false
        status = .disabled
        try? store.setSyncEnabled(false)
    }

    func setOffline(_ offline: Bool) {
        forceOffline = offline
        if offline {
            status = .offline
        } else if isSyncEnabled {
            status = .idle
            Task { await syncNow() }
        }
    }

    func syncNow() async {
        guard isSyncEnabled, !forceOffline else {
            if forceOffline { status = .offline }
            return
        }
        guard let encryptionKey else {
            status = .error("Sync key unavailable")
            return
        }

        syncTask?.cancel()
        syncTask = Task {
            await performSync(using: encryptionKey)
        }
        await syncTask?.value
    }

    func resolveConflict(keepLocal: Bool) async {
        guard let conflict else { return }
        do {
            let chosen = keepLocal ? conflict.local : conflict.remote
            try store.applySyncPayload(chosen, notifySync: false)
            try await uploadPayload(chosen, using: encryptionKey!)
            try store.saveSyncBase(chosen)
            self.conflict = nil
            status = .idle
        } catch {
            status = .error(error.localizedDescription)
        }
    }

    private func noteDidChange(noteID: String) {
        guard isSyncEnabled else { return }
        Task { await refreshPendingCount() }
        scheduleSyncDebounced()
    }

    private func scheduleSyncDebounced() {
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            await syncNow()
        }
    }

    private func performSync(using key: SymmetricKey) async {
        status = .syncing
        do {
            try await PerformanceSignpost.measure(.syncPerform) {
                try await pushPending(using: key)
                try await pullRemote(using: key)
                try store.updateLastSyncedAt(Date())
                await refreshPendingCount()
            }
            status = forceOffline ? .offline : .idle
        } catch SyncError.transportUnavailable {
            status = .offline
        } catch {
            status = .error("Couldn't sync — retrying…")
        }
    }

    private func pushPending(using key: SymmetricKey) async throws {
        let payloads = try store.pendingSyncPayloads()
        for payload in payloads {
            try await uploadPayload(payload, using: key)
            try store.saveSyncBase(payload)
        }
        try store.clearSyncQueue()
    }

    private func uploadPayload(_ payload: NoteSyncPayload, using key: SymmetricKey) async throws {
        let ciphertext = try SyncEncryption.encrypt(payload: payload, using: key)
        let record = EncryptedSyncRecord(
            noteID: payload.noteID,
            vaultID: payload.vaultID,
            ciphertext: ciphertext,
            version: payload.version,
            clientUpdatedAt: payload.clientUpdatedAt,
            isDeleted: payload.isDeleted
        )
        try await transport.upload(record, vaultID: payload.vaultID)
    }

    private func pullRemote(using key: SymmetricKey) async throws {
        let result = try await transport.fetchRemote(
            vaultID: store.meta.vaultID,
            since: changeToken
        )
        changeToken = result.changeToken

        for encrypted in result.records {
            let remote = try SyncEncryption.decrypt(encrypted.ciphertext, using: key)
            let local = try store.syncPayload(for: remote.noteID)
            let base = try store.syncBase(for: remote.noteID)

            if let local {
                switch NoteMerger.merge(local: local, remote: remote, base: base) {
                case .merged(let merged):
                    try store.applySyncPayload(merged, notifySync: false)
                    try store.saveSyncBase(merged)
                case .unchanged:
                    break
                case .conflict(let noteConflict):
                    conflict = noteConflict
                    status = .error("Sync conflict detected")
                    return
                }
            } else {
                try store.applySyncPayload(remote, notifySync: false)
                try store.saveSyncBase(remote)
            }
        }

        for deletedID in result.deletedNoteIDs {
            try store.softDeleteNote(id: deletedID, notifySync: false)
        }
    }

    private func refreshPendingCount() async {
        pendingUploadCount = (try? store.pendingSyncCount()) ?? 0
    }
}
