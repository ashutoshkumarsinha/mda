//
//  VaultDocument.swift
//  MDE
//

import Combine
import SwiftUI
import UniformTypeIdentifiers

final class VaultDocument: ReferenceFileDocument, ObservableObject {
    typealias Snapshot = VaultFileSnapshot

    @Published var store: VaultStore

    static var readableContentTypes: [UTType] { [.mdeDocument] }
    static var writableContentTypes: [UTType] { [.mdeDocument] }

    init() {
        store = VaultStore()
    }

    required init(configuration: ReadConfiguration) throws {
        store = VaultStore()
        try store.load(from: configuration.file)
    }

    func snapshot(contentType: UTType) throws -> VaultFileSnapshot {
        try store.makeSnapshot()
    }

    func fileWrapper(snapshot: VaultFileSnapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        snapshot.makeFileWrapper()
    }

    func bindToPackageIfNeeded(url: URL?) {
        guard let url else { return }
        do {
            try store.attachToPackage(at: url)
            objectWillChange.send()
        } catch let error as VaultError {
            if case .databaseCorrupt = error {
                store.needsDatabaseRecovery = true
                objectWillChange.send()
            } else {
                assertionFailure("Failed to attach vault to package: \(error)")
            }
        } catch {
            assertionFailure("Failed to attach vault to package: \(error)")
        }
    }
}

extension UTType {
    static var mdeDocument: UTType {
        UTType(importedAs: "name.aks.mde.document")
    }
}
