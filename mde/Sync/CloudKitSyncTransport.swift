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

        var fetched: [EncryptedSyncRecord] = []
        var deleted: [String] = []
        var newToken: CKServerChangeToken?

        let configuration = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        configuration.previousServerChangeToken = token
        let operation = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: configuration]
        )

        operation.recordWasChangedBlock = { _, result in
            if case .success(let ckRecord) = result,
               let encrypted = Self.encryptedRecord(from: ckRecord, vaultID: vaultID) {
                fetched.append(encrypted)
            }
        }

        operation.recordWithIDWasDeletedBlock = { recordID, _ in
            deleted.append(recordID.recordName)
        }

        operation.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            newToken = token
        }

        operation.recordZoneFetchResultBlock = { _, result in
            if case .success(let zoneResult) = result {
                newToken = zoneResult.serverChangeToken
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
        if let newToken {
            encodedToken = try NSKeyedArchiver.archivedData(
                withRootObject: newToken,
                requiringSecureCoding: true
            )
        } else {
            encodedToken = changeToken
        }

        return SyncFetchResult(records: fetched, deletedNoteIDs: deleted, changeToken: encodedToken)
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

    private static func encryptedRecord(from record: CKRecord, vaultID: String) -> EncryptedSyncRecord? {
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
}
