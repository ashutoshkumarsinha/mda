//
//  MDEApp.swift
//  MDE
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

#if os(macOS)
private final class MDEAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !LaunchArguments.benchmarkColdLaunch
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard LaunchArguments.benchmarkColdLaunch else { return }
        guard NSDocumentController.shared.documents.isEmpty else { return }
        guard let vaultPath = ProcessInfo.processInfo.arguments.first(where: { $0.hasSuffix(".mde") }) else {
            return
        }
        let url = URL(fileURLWithPath: vaultPath)
        NSDocumentController.shared.openDocument(withContentsOf: url, display: true) { _, _, _ in }
    }
}
#endif

@main
struct MDEApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(MDEAppDelegate.self) private var appDelegate

    init() {
        ColdLaunchBenchmark.exitIfCreateBenchmarkVaultRequested()
    }
    #endif

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
