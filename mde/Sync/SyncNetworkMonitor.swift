//
//  SyncNetworkMonitor.swift
//  MDE
//

import Foundation
import Network

@MainActor
final class SyncNetworkMonitor {
    private let monitor = NWPathMonitor()
    private var isStarted = false

    func start(handler: @escaping @MainActor (Bool) -> Void) {
        guard !isStarted else { return }
        isStarted = true
        monitor.pathUpdateHandler = { path in
            let online = path.status == .satisfied
            Task { @MainActor in
                handler(online)
            }
        }
        monitor.start(queue: DispatchQueue(label: "name.aks.mde.sync-network"))
    }

    func stop() {
        monitor.cancel()
        isStarted = false
    }
}
