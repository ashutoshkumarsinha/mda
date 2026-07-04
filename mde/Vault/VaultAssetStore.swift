//
//  VaultAssetStore.swift
//  MDE
//

import Foundation
import GRDB
import UniformTypeIdentifiers

enum VaultAssetStore {
    private static let allowedExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic"]

    static func markdownPath(for asset: VaultAsset) -> String {
        "assets/\(asset.filename)"
    }

    static func markdownReference(alt: String, asset: VaultAsset) -> String {
        let escapedAlt = alt.replacingOccurrences(of: "]", with: "\\]")
        return "![\(escapedAlt)](\(markdownPath(for: asset)))"
    }

    static func mimeType(forExtension ext: String) -> String? {
        switch ext.lowercased() {
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "gif": return "image/gif"
        case "webp": return "image/webp"
        case "heic": return "image/heic"
        default: return nil
        }
    }

    static func normalizedExtension(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if allowedExtensions.contains(ext) { return ext == "jpeg" ? "jpg" : ext }
        if let type = UTType(filenameExtension: ext),
           let preferred = type.preferredFilenameExtension?.lowercased(),
           allowedExtensions.contains(preferred) {
            return preferred == "jpeg" ? "jpg" : preferred
        }
        return nil
    }

    static func writeAsset(
        data: Data,
        asset: VaultAsset,
        packageURL: URL
    ) throws {
        let destination = VaultPaths.assetFileURL(in: packageURL, filename: asset.filename)
        try FileManager.default.createDirectory(at: VaultPaths.assetsURL(in: packageURL), withIntermediateDirectories: true)
        try data.write(to: destination, options: .atomic)
    }

    static func readAssetData(asset: VaultAsset, packageURL: URL) throws -> Data {
        let url = VaultPaths.assetFileURL(in: packageURL, filename: asset.filename)
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw VaultAssetError.assetNotFound
        }
        return try Data(contentsOf: url)
    }

    static func assetFileExists(_ asset: VaultAsset, packageURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: VaultPaths.assetFileURL(in: packageURL, filename: asset.filename).path)
    }

    /// Parses `assets/<filename>` from a markdown image target; rejects traversal.
    static func parseVaultAssetPath(_ target: String) -> String? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("assets/") else { return nil }
        let filename = String(trimmed.dropFirst("assets/".count))
        guard !filename.isEmpty,
              !filename.contains(".."),
              !filename.contains("/"),
              !filename.contains("\\") else {
            return nil
        }
        return filename
    }
}
