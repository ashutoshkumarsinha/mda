//
//  SyncEncryption.swift
//  MDE
//

import CryptoKit
import Foundation

enum SyncError: LocalizedError {
    case encryptionFailed
    case decryptionFailed
    case keyUnavailable
    case transportUnavailable
    case recordTooLarge(Int)
    case assetUnavailable
    case assetTooLarge(Int)

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Could not encrypt note for sync."
        case .decryptionFailed: return "Could not decrypt synced note."
        case .keyUnavailable: return "Sync encryption key is not available."
        case .transportUnavailable: return "Sync transport is not available."
        case .recordTooLarge(let bytes):
            return "Encrypted note exceeds \(bytes) bytes (limit \(SyncPolicy.maxRecordBytes))."
        case .assetUnavailable:
            return "Save the vault to a package before syncing images."
        case .assetTooLarge(let bytes):
            return "Encrypted asset exceeds \(bytes) bytes (limit \(SyncPolicy.maxAssetRecordBytes))."
        }
    }
}

enum SyncEncryption {
    static func generateKey() -> SymmetricKey {
        SymmetricKey(size: .bits256)
    }

    static func encrypt(payload: NoteSyncPayload, using key: SymmetricKey) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(payload)
        let sealed = try AES.GCM.seal(data, using: key)
        guard let combined = sealed.combined else { throw SyncError.encryptionFailed }
        return combined
    }

    static func decrypt(_ data: Data, using key: SymmetricKey) throws -> NoteSyncPayload {
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(NoteSyncPayload.self, from: decrypted)
    }

    private struct AssetSyncEnvelope: Codable {
        var payload: AssetSyncPayload
        var data: Data
    }

    static func encrypt(
        payload: AssetSyncPayload,
        data: Data,
        using key: SymmetricKey
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let envelope = AssetSyncEnvelope(payload: payload, data: data)
        let encoded = try encoder.encode(envelope)
        let sealed = try AES.GCM.seal(encoded, using: key)
        guard let combined = sealed.combined else { throw SyncError.encryptionFailed }
        return combined
    }

    static func decryptAsset(_ data: Data, using key: SymmetricKey) throws -> (AssetSyncPayload, Data) {
        let box = try AES.GCM.SealedBox(combined: data)
        let decrypted = try AES.GCM.open(box, using: key)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let envelope = try decoder.decode(AssetSyncEnvelope.self, from: decrypted)
        return (envelope.payload, envelope.data)
    }
}
