//
//  VaultMeta.swift
//  MDE
//

import Foundation

struct VaultMeta: Codable, Equatable, Sendable {
    var formatVersion: Int
    var vaultID: String
    var createdAt: Date

    enum CodingKeys: String, CodingKey {
        case formatVersion = "format_version"
        case vaultID = "vault_id"
        case createdAt = "created_at"
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
