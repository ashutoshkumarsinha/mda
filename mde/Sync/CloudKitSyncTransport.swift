//
//  CloudKitSyncTransport.swift
//  MDE
//

import CloudKit
import Foundation

actor CloudKitSyncTransport: SyncTransport {
    private let container: CKContainer
    private let database: CKDatabase
    private var preparedZones: Set<String> = []

    init(containerIdentifier: String = "iCloud.name.aks.mde") {
        container = CKContainer(identifier: containerIdentifier)
        database = container.privateCloudDatabase
    }

    func upload(_ record: EncryptedSyncRecord, vaultID: String) async throws {
        let zoneID = try await ensureZone(vaultID: vaultID)
        let ckRecord = CKRecord(recordType: "MDENote", recordID: CKRecord.ID(recordName: record.noteID, zoneID: zoneID))
        ckRecord["ciphertext"] = record.ciphertext as CKRecordValue
        ckRecord["version"] = record.version as CKRecordValue
        ckRecord["clientUpdatedAt"] = record.clientUpdatedAt as CKRecordValue
        ckRecord["isDeleted"] = (record.isDeleted ? 1 : 0) as CKRecordValue
        ckRecord["vaultID"] = vaultID as CKRecordValue
        _ = try await database.save(ckRecord)
    }

    func uploadAsset(_ record: EncryptedAssetSyncRecord, vaultID: String) async throws {
        let zoneID = try await ensureZone(vaultID: vaultID)
        let ckRecord = CKRecord(recordType: "MDEAsset", recordID: CKRecord.ID(recordName: record.assetID, zoneID: zoneID))
        ckRecord["vaultID"] = vaultID as CKRecordValue
        ckRecord["filename"] = record.filename as CKRecordValue
        ckRecord["mimeType"] = record.mimeType as CKRecordValue
        ckRecord["byteSize"] = record.byteSize as CKRecordValue
        ckRecord["contentChecksum"] = record.contentChecksum as CKRecordValue

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("mde-asset-\(record.assetID).bin")
        try record.ciphertext.write(to: tempURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: tempURL) }
        ckRecord["ciphertext"] = CKAsset(fileURL: tempURL)

        _ = try await database.save(ckRecord)
    }

    func fetchRemote(vaultID: String, since changeToken: Data?) async throws -> SyncFetchResult {
        let zoneID = try await ensureZone(vaultID: vaultID)
        let token: CKServerChangeToken?
        if let changeToken, !changeToken.isEmpty {
            token = try NSKeyedUnarchiver.unarchivedObject(
                ofClass: CKServerChangeToken.self,
                from: changeToken
            )
        } else {
            token = nil
        }

        let results = FetchResultsBox()

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = token
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )

        operation.recordWasChangedBlock = { _, result in
            if case .success(let ckRecord) = result {
                switch ckRecord.recordType {
                case "MDENote":
                    if let encrypted = CloudKitRecordParser.encryptedRecord(from: ckRecord, vaultID: vaultID) {
                        results.addRecord(encrypted)
                    }
                case "MDEAsset":
                    if let encrypted = CloudKitRecordParser.encryptedAssetRecord(from: ckRecord, vaultID: vaultID) {
                        results.addAssetRecord(encrypted)
                    }
                default:
                    break
                }
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, recordType in
            switch recordType {
            case "MDENote":
                results.addDeleted(recordID.recordName)
            case "MDEAsset":
                results.addDeletedAsset(recordID.recordName)
            default:
                break
            }
        }

        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            results.setChangeToken(token)
        }

        operation.recordZoneFetchResultBlock = { _, result in
            if case .success(let zoneResult) = result {
                results.setChangeToken(zoneResult.serverChangeToken)
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            operation.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success:
                    continuation.resume()
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
            database.add(operation)
        }

        let encodedToken: Data?
        if let newToken = results.changeToken {
            encodedToken = try NSKeyedArchiver.archivedData(
                withRootObject: newToken,
                requiringSecureCoding: true
            )
        } else {
            encodedToken = changeToken
        }

        return SyncFetchResult(
            records: results.records,
            assetRecords: results.assetRecords,
            deletedNoteIDs: results.deletedNoteIDs,
            deletedAssetIDs: results.deletedAssetIDs,
            changeToken: encodedToken
        )
    }

    private func ensureZone(vaultID: String) async throws -> CKRecordZone.ID {
        if preparedZones.contains(vaultID) {
            return CKRecordZone.ID(zoneName: "MDE-\(vaultID)")
        }

        let zoneID = CKRecordZone.ID(zoneName: "MDE-\(vaultID)")
        _ = try await database.modifyRecordZones(saving: [CKRecordZone(zoneID: zoneID)], deleting: [])
        preparedZones.insert(vaultID)
        return zoneID
    }

    func fetchAsset(assetID: String, vaultID: String) async throws -> EncryptedAssetSyncRecord? {
        let zoneID = try await ensureZone(vaultID: vaultID)
        let recordID = CKRecord.ID(recordName: assetID, zoneID: zoneID)
        let ckRecord = try await database.record(for: recordID)
        guard ckRecord.recordType == "MDEAsset" else { return nil }
        return CloudKitRecordParser.encryptedAssetRecord(from: ckRecord, vaultID: vaultID)
    }
}

private enum CloudKitRecordParser {
    nonisolated static func encryptedRecord(from record: CKRecord, vaultID: String) -> EncryptedSyncRecord? {
        guard let ciphertext = record["ciphertext"] as? Data,
              let version = record["version"] as? Int,
              let clientUpdatedAt = record["clientUpdatedAt"] as? Date else {
            return nil
        }
        let isDeleted = (record["isDeleted"] as? Int ?? 0) != 0
        return EncryptedSyncRecord(
            noteID: record.recordID.recordName,
            vaultID: vaultID,
            ciphertext: ciphertext,
            version: version,
            clientUpdatedAt: clientUpdatedAt,
            isDeleted: isDeleted
        )
    }

    nonisolated static func encryptedAssetRecord(from record: CKRecord, vaultID: String) -> EncryptedAssetSyncRecord? {
        guard let filename = record["filename"] as? String,
              let mimeType = record["mimeType"] as? String,
              let byteSize = record["byteSize"] as? Int64,
              let contentChecksum = record["contentChecksum"] as? String else {
            return nil
        }

        let ciphertext: Data?
        if let data = record["ciphertext"] as? Data {
            ciphertext = data
        } else if let asset = record["ciphertext"] as? CKAsset, let url = asset.fileURL {
            ciphertext = try? Data(contentsOf: url)
        } else {
            ciphertext = nil
        }
        guard let ciphertext else { return nil }

        return EncryptedAssetSyncRecord(
            assetID: record.recordID.recordName,
            vaultID: vaultID,
            ciphertext: ciphertext,
            filename: filename,
            mimeType: mimeType,
            byteSize: byteSize,
            contentChecksum: contentChecksum
        )
    }
}

private final class FetchResultsBox: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var records: [EncryptedSyncRecord] = []
    private(set) var assetRecords: [EncryptedAssetSyncRecord] = []
    private(set) var deletedNoteIDs: [String] = []
    private(set) var deletedAssetIDs: [String] = []
    private(set) var changeToken: CKServerChangeToken?

    func addRecord(_ record: EncryptedSyncRecord) {
        lock.lock()
        records.append(record)
        lock.unlock()
    }

    func addAssetRecord(_ record: EncryptedAssetSyncRecord) {
        lock.lock()
        assetRecords.append(record)
        lock.unlock()
    }

    func addDeleted(_ noteID: String) {
        lock.lock()
        deletedNoteIDs.append(noteID)
        lock.unlock()
    }

    func addDeletedAsset(_ assetID: String) {
        lock.lock()
        deletedAssetIDs.append(assetID)
        lock.unlock()
    }

    func setChangeToken(_ token: CKServerChangeToken?) {
        lock.lock()
        changeToken = token
        lock.unlock()
    }
}
