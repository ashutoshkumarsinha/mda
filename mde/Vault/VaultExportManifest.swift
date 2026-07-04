//
//  VaultExportManifest.swift
//  MDE
//

import Foundation

/// Portable export manifest written to `meta.json` in v2.3 package / zip exports.
struct VaultExportManifest: Codable, Equatable, Sendable {
    static let exportVersion = 1

    var exportVersion: Int
    var vaultID: String
    var exportedAt: Date
    var notes: [NoteEntry]
    var assets: [AssetEntry]

    struct NoteEntry: Codable, Equatable, Sendable {
        var id: String
        var title: String
        var path: String
    }

    struct AssetEntry: Codable, Equatable, Sendable {
        var id: String
        var path: String
        var mimeType: String
    }

    enum CodingKeys: String, CodingKey {
        case exportVersion = "export_version"
        case vaultID = "vault_id"
        case exportedAt = "exported_at"
        case notes, assets
    }

    func data() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    static func decode(from data: Data) throws -> VaultExportManifest {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(VaultExportManifest.self, from: data)
    }
}

enum VaultPackageExport {
    static let notesDirectoryName = "notes"
    static let assetsDirectoryName = VaultPaths.assetsDirectoryName
    static let manifestFileName = VaultPaths.metaFileName
}

enum VaultExportError: LocalizedError {
    case noteNotFound
    case assetsUnavailable

    var errorDescription: String? {
        switch self {
        case .noteNotFound:
            return "Note was not found."
        case .assetsUnavailable:
            return "Save the vault to a package before exporting notes with images."
        }
    }
}
