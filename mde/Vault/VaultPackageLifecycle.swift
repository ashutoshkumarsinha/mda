//
//  VaultPackageLifecycle.swift
//  MDE
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

struct VaultPackageLifecycleModifier: ViewModifier {
    let store: VaultStore

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        content
            #if os(iOS)
            .onChange(of: scenePhase) { _, phase in
                if phase == .background {
                    flushPackage()
                }
            }
            #endif
            #if os(macOS)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                flushPackage()
            }
            #endif
    }

    private func flushPackage() {
        try? store.flushPackageIfNeeded()
    }
}

extension View {
    func vaultPackageLifecycle(store: VaultStore) -> some View {
        modifier(VaultPackageLifecycleModifier(store: store))
    }
}
