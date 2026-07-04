//
//  SyncTransport.swift
//  MDE
//

import Foundation

protocol SyncTransport: Sendable {
    func upload(_ record: EncryptedSyncRecord, vaultID: String) async throws
    func uploadAsset(_ record: EncryptedAssetSyncRecord, vaultID: String) async throws
    func fetchRemote(vaultID: String, since changeToken: Data?) async throws -> SyncFetchResult
}

final class InMemorySyncTransport: SyncTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var records: [String: [String: EncryptedSyncRecord]] = [:]
    private var assetRecords: [String: [String: EncryptedAssetSyncRecord]] = [:]
    private(set) var uploadCount = 0
    private(set) var assetUploadCount = 0
    private(set) var fetchCount = 0
    var isOffline = false

    func upload(_ record: EncryptedSyncRecord, vaultID: String) async throws {
        if isOffline { throw SyncError.transportUnavailable }
        lock.lock()
        defer { lock.unlock() }
        records[vaultID, default: [:]][record.noteID] = record
        uploadCount += 1
    }

    func uploadAsset(_ record: EncryptedAssetSyncRecord, vaultID: String) async throws {
        if isOffline { throw SyncError.transportUnavailable }
        lock.lock()
        defer { lock.unlock() }
        assetRecords[vaultID, default: [:]][record.assetID] = record
        assetUploadCount += 1
    }

    func fetchRemote(vaultID: String, since changeToken: Data?) async throws -> SyncFetchResult {
        if isOffline { throw SyncError.transportUnavailable }
        lock.lock()
        fetchCount += 1
        defer { lock.unlock() }
        let vaultRecords = records[vaultID] ?? [:]
        let vaultAssets = assetRecords[vaultID] ?? [:]
        return SyncFetchResult(
            records: Array(vaultRecords.values),
            assetRecords: Array(vaultAssets.values),
            deletedNoteIDs: [],
            deletedAssetIDs: [],
            changeToken: Data("token-\(vaultRecords.count)-\(vaultAssets.count)".utf8)
        )
    }

    func allRecords(vaultID: String) -> [EncryptedSyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(records[vaultID]?.values ?? [:].values)
    }

    func allAssetRecords(vaultID: String) -> [EncryptedAssetSyncRecord] {
        lock.lock()
        defer { lock.unlock() }
        return Array(assetRecords[vaultID]?.values ?? [:].values)
    }
}
