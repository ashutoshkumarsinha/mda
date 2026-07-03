//
//  SyncLifecycle.swift
//  MDE
//

import SwiftUI

struct SyncLifecycleModifier: ViewModifier {
    let coordinator: SyncCoordinator
    let networkMonitor: SyncNetworkMonitor

    #if os(iOS)
    @Environment(\.scenePhase) private var scenePhase
    #endif

    func body(content: Content) -> some View {
        content
            .task {
                networkMonitor.start { online in
                    coordinator.setOffline(!online)
                }
            }
            .onDisappear {
                networkMonitor.stop()
            }
            #if os(iOS)
            .onChange(of: scenePhase) { _, phase in
                coordinator.setBackgroundPaused(phase == .background)
            }
            #endif
    }
}

extension View {
    func syncLifecycle(coordinator: SyncCoordinator, networkMonitor: SyncNetworkMonitor) -> some View {
        modifier(SyncLifecycleModifier(coordinator: coordinator, networkMonitor: networkMonitor))
    }
}
