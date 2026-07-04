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

    var vaultID: String { store.meta.vaultID }

    func conflictLogEntries() -> [SyncConflictLogEntry] {
        SyncConflictLog.entries(vaultID: vaultID)
    }

    private let store: VaultStore
    private let transport: SyncTransport
    private let keyStore: SyncKeyStoring
    private var encryptionKey: SymmetricKey?
    private var changeToken: Data?
    private var syncTask: Task<Void, Never>?
    private var forceOffline = false
    private var backgroundPaused = false

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
        self.changeToken = store.meta.cloudChangeToken
        store.onNoteChanged = { [weak self] noteID in
            self?.noteDidChange(noteID: noteID)
        }
    }

    func bootstrap() async {
        guard isSyncEnabled else { return }
        encryptionKey = try? keyStore.loadKey(vaultID: store.meta.vaultID)
        changeToken = store.meta.cloudChangeToken
        await refreshPendingCount()

        if pendingUploadCount > 0 {
            await runSync(includePull: shouldPullRemote())
        } else if shouldPullRemote() {
            await runPullOnly()
        } else {
            status = forceOffline ? .offline : .idle
        }
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
        await syncNow(forceFull: true)
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

    func setBackgroundPaused(_ paused: Bool) {
        backgroundPaused = paused
        if paused {
            syncTask?.cancel()
        }
    }

    func syncNow(forceFull: Bool = false) async {
        guard isSyncEnabled, !forceOffline else {
            if forceOffline { status = .offline }
            return
        }
        if backgroundPaused && !forceFull { return }
        guard encryptionKey != nil else {
            status = .error("Sync key unavailable")
            return
        }

        syncTask?.cancel()
        syncTask = Task {
            await runSync(includePull: forceFull || shouldPullRemote())
        }
        await syncTask?.value
    }

    func resolveConflict(keepLocal: Bool) async {
        guard let conflict, let encryptionKey else { return }
        do {
            let chosen = keepLocal ? conflict.local : conflict.remote
            try store.applySyncPayload(chosen, notifySync: false)
            try await uploadPayload(chosen, using: encryptionKey)
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
        guard !backgroundPaused else { return }
        scheduleSyncDebounced()
    }

    private func scheduleSyncDebounced() {
        guard !backgroundPaused else { return }
        syncTask?.cancel()
        syncTask = Task {
            try? await Task.sleep(for: .seconds(SyncPolicy.editDebounceSeconds))
            guard !Task.isCancelled, !backgroundPaused else { return }
            await syncNow(forceFull: false)
        }
    }

    private func shouldPullRemote() -> Bool {
        if changeToken == nil { return true }
        guard let lastSynced = store.meta.lastSyncedAt else { return true }
        return Date().timeIntervalSince(lastSynced) >= SyncPolicy.minPullIntervalSeconds
    }

    private func runSync(includePull: Bool) async {
        guard let encryptionKey else {
            status = .error("Sync key unavailable")
            return
        }

        status = .syncing
        do {
            try await PerformanceSignpost.measure(.syncPerform) {
                try await pushPending(using: encryptionKey)
                if includePull {
                    try await pullRemote(using: encryptionKey)
                }
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

    private func runPullOnly() async {
        guard let encryptionKey else { return }
        status = .syncing
        do {
            try await pullRemote(using: encryptionKey)
            try store.updateLastSyncedAt(Date())
            status = forceOffline ? .offline : .idle
        } catch SyncError.transportUnavailable {
            status = .offline
        } catch {
            status = .error("Couldn't sync — retrying…")
        }
    }

    private func pushPending(using key: SymmetricKey) async throws {
        try await pushPendingAssets(using: key)

        let payloads = try store.pendingSyncPayloads()
        for payload in payloads {
            if let uploaded = try store.syncBase(for: payload.noteID),
               uploaded.checksum == payload.checksum {
                try store.dequeueSync(noteID: payload.noteID)
                continue
            }
            try await uploadPayload(payload, using: key)
            try store.saveSyncBase(payload)
            try store.dequeueSync(noteID: payload.noteID)
        }
    }

    private func pushPendingAssets(using key: SymmetricKey) async throws {
        let pending = try store.pendingAssetSyncPayloads()
        for (payload, data) in pending {
            if let uploadedChecksum = try store.assetSyncBaseChecksum(for: payload.assetID),
               uploadedChecksum == payload.contentChecksum {
                try store.dequeueAssetSync(assetID: payload.assetID)
                continue
            }
            try await uploadAsset(payload: payload, data: data, using: key)
            try store.saveAssetSyncBase(assetID: payload.assetID, contentChecksum: payload.contentChecksum)
            try store.dequeueAssetSync(assetID: payload.assetID)
        }
    }

    private func uploadAsset(
        payload: AssetSyncPayload,
        data: Data,
        using key: SymmetricKey
    ) async throws {
        let ciphertext = try SyncEncryption.encrypt(payload: payload, data: data, using: key)
        guard ciphertext.count <= SyncPolicy.maxAssetRecordBytes else {
            throw SyncError.assetTooLarge(ciphertext.count)
        }
        let record = EncryptedAssetSyncRecord(
            assetID: payload.assetID,
            vaultID: payload.vaultID,
            ciphertext: ciphertext,
            filename: payload.filename,
            mimeType: payload.mimeType,
            byteSize: payload.byteSize,
            contentChecksum: payload.contentChecksum
        )
        try await transport.uploadAsset(record, vaultID: payload.vaultID)
    }

    private func uploadPayload(_ payload: NoteSyncPayload, using key: SymmetricKey) async throws {
        let ciphertext = try SyncEncryption.encrypt(payload: payload, using: key)
        guard ciphertext.count <= SyncPolicy.maxRecordBytes else {
            throw SyncError.recordTooLarge(ciphertext.count)
        }
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
        persistChangeToken(result.changeToken)

        for encryptedAsset in result.assetRecords {
            let (payload, data) = try SyncEncryption.decryptAsset(encryptedAsset.ciphertext, using: key)
            guard payload.assetID == encryptedAsset.assetID,
                  payload.contentChecksum == encryptedAsset.contentChecksum else {
                continue
            }
            if try store.assetSyncBaseChecksum(for: payload.assetID) == payload.contentChecksum {
                continue
            }
            try store.applyRemoteAsset(payload, data: data)
        }

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
                    SyncConflictLog.append(
                        noteID: noteConflict.local.noteID,
                        title: noteConflict.local.title,
                        vaultID: store.meta.vaultID
                    )
                    status = .error("Sync conflict detected")
                    return
                }
            } else {
                try store.applySyncPayload(remote, notifySync: false)
                try store.saveSyncBase(remote)
            }
        }

        try await supplementMissingAssets(from: result.records, using: key)

        for deletedID in result.deletedNoteIDs {
            try store.softDeleteNote(id: deletedID, notifySync: false)
        }
    }

    private func supplementMissingAssets(
        from records: [EncryptedSyncRecord],
        using key: SymmetricKey
    ) async throws {
        guard store.isPackageAttached else { return }

        for encrypted in records {
            let remote = try SyncEncryption.decrypt(encrypted.ciphertext, using: key)
            guard !remote.isDeleted else { continue }

            for assetID in store.missingReferencedAssetIDs(in: remote.content) {
                guard let encryptedAsset = try await transport.fetchAsset(
                    assetID: assetID,
                    vaultID: store.meta.vaultID
                ) else {
                    continue
                }
                let (payload, data) = try SyncEncryption.decryptAsset(encryptedAsset.ciphertext, using: key)
                guard payload.assetID == assetID,
                      payload.contentChecksum == encryptedAsset.contentChecksum else {
                    continue
                }
                if try store.assetSyncBaseChecksum(for: assetID) == payload.contentChecksum {
                    continue
                }
                try store.applyRemoteAsset(payload, data: data)
            }
        }
    }

    private func persistChangeToken(_ token: Data?) {
        changeToken = token
        try? store.updateCloudChangeToken(token)
    }

    private func refreshPendingCount() async {
        pendingUploadCount = (try? store.pendingSyncCount()) ?? 0
    }
}
