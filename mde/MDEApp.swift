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
    @State private var isPackageBound = false

    var body: some View {
        ContentView(store: document.store, isPackageBound: isPackageBound)
            .onAppear {
                document.bindToPackageIfNeeded(url: configuration.fileURL)
                isPackageBound = document.store.isPackageAttached
            }
            .onChange(of: configuration.fileURL) { _, newURL in
                document.bindToPackageIfNeeded(url: newURL)
                isPackageBound = document.store.isPackageAttached
            }
    }
}
