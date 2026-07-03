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

    var errorDescription: String? {
        switch self {
        case .encryptionFailed: return "Could not encrypt note for sync."
        case .decryptionFailed: return "Could not decrypt synced note."
        case .keyUnavailable: return "Sync encryption key is not available."
        case .transportUnavailable: return "Sync transport is not available."
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
}
