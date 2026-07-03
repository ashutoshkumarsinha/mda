//
//  VaultMeta.swift
//  MDE
//

import Foundation

struct VaultMeta: Codable, Equatable, Sendable {
    var formatVersion: Int
    var vaultID: String
    var createdAt: Date
    var syncEnabled: Bool
    var lastSyncedAt: Date?

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case vaultID = "vault_id"
        case createdAt = "created_at"
        case syncEnabled = "sync_enabled"
        case lastSyncedAt = "last_synced_at"
    }

    init(
        formatVersion: Int,
        vaultID: String,
        createdAt: Date,
        syncEnabled: Bool = false,
        lastSyncedAt: Date? = nil
    ) {
        self.formatVersion = formatVersion
        self.vaultID = vaultID
        self.createdAt = createdAt
        self.syncEnabled = syncEnabled
        self.lastSyncedAt = lastSyncedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        vaultID = try container.decode(String.self, forKey: .vaultID)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        syncEnabled = try container.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        lastSyncedAt = try container.decodeIfPresent(Date.self, forKey: .lastSyncedAt)
    }

    static func makeNew() -> VaultMeta {
        VaultMeta(
            formatVersion: VaultPaths.formatVersion,
            vaultID: UUID().uuidString,
            createdAt: Date()
        )
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> VaultMeta {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultMeta.self, from: data)
    }
}
