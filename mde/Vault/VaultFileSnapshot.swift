//
//  VaultFileSnapshot.swift
//  MDE
//

import Foundation
import UniformTypeIdentifiers

struct VaultFileSnapshot: Sendable {
    var meta: VaultMeta
    var databaseData: Data

    func makeFileWrapper() -> FileWrapper {
        let metaWrapper = FileWrapper(regularFileWithContents: (try? meta.data()) ?? Data())
        let databaseWrapper = FileWrapper(regularFileWithContents: databaseData)
        let assetsWrapper = FileWrapper(directoryWithFileWrappers: [:])

        return FileWrapper(directoryWithFileWrappers: [
            VaultPaths.metaFileName: metaWrapper,
            VaultPaths.databaseFileName: databaseWrapper,
            VaultPaths.assetsDirectoryName: assetsWrapper,
        ])
    }

    static func load(from fileWrapper: FileWrapper) throws -> VaultFileSnapshot {
        guard let children = fileWrapper.fileWrappers else {
            throw VaultError.invalidPackage("Missing package contents")
        }

        guard let metaWrapper = children[VaultPaths.metaFileName],
              let metaData = metaWrapper.regularFileContents else {
            throw VaultError.invalidPackage("Missing \(VaultPaths.metaFileName)")
        }

        guard let databaseWrapper = children[VaultPaths.databaseFileName],
              let databaseData = databaseWrapper.regularFileContents else {
            throw VaultError.invalidPackage("Missing \(VaultPaths.databaseFileName)")
        }

        let meta = try VaultMeta.decode(from: metaData)
        return VaultFileSnapshot(meta: meta, databaseData: databaseData)
    }
}

enum VaultError: LocalizedError {
    case invalidPackage(String)
    case databaseUnavailable
    case databaseCorrupt(backupAvailable: Bool)

    var errorDescription: String? {
        switch self {
        case .invalidPackage(let reason):
            return "Invalid vault package: \(reason)"
        case .databaseUnavailable:
            return "Vault database is not available"
        case .databaseCorrupt(let backupAvailable):
            if backupAvailable {
                return "The vault database appears damaged. You can restore from the last automatic backup."
            }
            return "The vault database appears damaged and no backup is available."
        }
    }
}
