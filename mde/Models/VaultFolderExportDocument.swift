//
//  VaultFolderExportDocument.swift
//  MDE
//

import SwiftUI
import UniformTypeIdentifiers

/// FileDocument wrapper for exporting a vault as a directory of `.md` files.
struct VaultFolderExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.folder] }
    static var writableContentTypes: [UTType] { [.folder] }

    var wrapper: FileWrapper

    init(wrapper: FileWrapper = FileWrapper(directoryWithFileWrappers: [:])) {
        self.wrapper = wrapper
    }

    init(configuration: ReadConfiguration) throws {
        wrapper = configuration.file
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        wrapper
    }
}
