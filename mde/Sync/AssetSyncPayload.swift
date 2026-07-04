//
//  AssetSyncPayload.swift
//  MDE
//

import CryptoKit
import Foundation

struct AssetSyncPayload: Codable, Equatable, Sendable {
    var assetID: String
    var vaultID: String
    var filename: String
    var mimeType: String
    var byteSize: Int64
    var contentChecksum: String
    var createdAt: Date

    init(asset: VaultAsset, vaultID: String, contentChecksum: String) {
        assetID = asset.id
        self.vaultID = vaultID
        filename = asset.filename
        mimeType = asset.mimeType
        byteSize = asset.byteSize
        self.contentChecksum = contentChecksum
        createdAt = asset.createdAt
    }
}

nonisolated struct EncryptedAssetSyncRecord: Equatable, Sendable {
    var assetID: String
    var vaultID: String
    var ciphertext: Data
    var filename: String
    var mimeType: String
    var byteSize: Int64
    var contentChecksum: String
}

enum AssetSyncChecksum {
    static func compute(for data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}
