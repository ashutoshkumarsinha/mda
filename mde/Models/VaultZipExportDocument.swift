//
//  VaultZipExportDocument.swift
//  MDE
//

import SwiftUI
import UniformTypeIdentifiers

/// FileDocument wrapper for exporting a vault or note package as a `.zip` archive.
struct VaultZipExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.zip] }
    static var writableContentTypes: [UTType] { [.zip] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
