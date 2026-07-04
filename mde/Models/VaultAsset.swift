//
//  VaultAsset.swift
//  MDE
//
//  v2 — binary assets stored under vault assets/ with DB metadata.
//

import Foundation
import GRDB

struct VaultAsset: Codable, FetchableRecord, MutablePersistableRecord, Identifiable, Sendable, Equatable {
    var id: String
    var filename: String
    var mimeType: String
    var byteSize: Int64
    var createdAt: Date

    static let databaseTableName = "vault_asset"

    enum CodingKeys: String, CodingKey {
        case id, filename
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case createdAt = "created_at"
    }

    enum Columns: String, ColumnExpression {
        case id, filename
        case mimeType = "mime_type"
        case byteSize = "byte_size"
        case createdAt = "created_at"
    }
}

struct NoteAsset: Codable, FetchableRecord, MutablePersistableRecord, Sendable, Equatable {
    var noteID: String
    var assetID: String
    var altText: String

    static let databaseTableName = "note_asset"

    enum CodingKeys: String, CodingKey {
        case noteID = "note_id"
        case assetID = "asset_id"
        case altText = "alt_text"
    }

    enum Columns: String, ColumnExpression {
        case noteID = "note_id"
        case assetID = "asset_id"
        case altText = "alt_text"
    }
}

enum VaultAssetError: LocalizedError {
    case packageNotAttached
    case unsupportedImageType(String)
    case assetNotFound
    case invalidAssetPath

    var errorDescription: String? {
        switch self {
        case .packageNotAttached:
            return "Save the vault to a package before adding images."
        case .unsupportedImageType(let ext):
            return "Unsupported image type: .\(ext)"
        case .assetNotFound:
            return "Image asset was not found in this vault."
        case .invalidAssetPath:
            return "Image path must be vault-relative under assets/."
        }
    }
}
