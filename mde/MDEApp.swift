//
//  MDEApp.swift
//  MDE
//

import SwiftUI

@main
struct MDEApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: VaultDocument.init) { configuration in
            VaultDocumentView(document: configuration.document, configuration: configuration)
        }
    }
}

private struct VaultDocumentView: View {
    @ObservedObject var document: VaultDocument
    let configuration: ReferenceFileDocumentConfiguration<VaultDocument>

    var body: some View {
        ContentView(store: document.store)
            .onAppear {
                document.bindToPackageIfNeeded(url: configuration.fileURL)
            }
            .onChange(of: configuration.fileURL) { _, newURL in
                document.bindToPackageIfNeeded(url: newURL)
            }
    }
}
