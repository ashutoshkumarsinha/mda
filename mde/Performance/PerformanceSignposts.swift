//
//  PerformanceSignposts.swift
//  MDE
//

import Foundation
import OSLog

enum PerformanceSignpost {
    case vaultRefreshAll
    case vaultReloadNotes
    case vaultReloadTagTree
    case vaultResolveLinks
    case vaultUpdateNote
    case vaultPersistPackage
    case vaultExportDatabase
    case markdownParse
    case markdownStyle
    case syncPerform

    var name: StaticString {
        switch self {
        case .vaultRefreshAll: "vault_refresh_all"
        case .vaultReloadNotes: "vault_reload_notes"
        case .vaultReloadTagTree: "vault_reload_tag_tree"
        case .vaultResolveLinks: "vault_resolve_links"
        case .vaultUpdateNote: "vault_update_note"
        case .vaultPersistPackage: "vault_persist_package"
        case .vaultExportDatabase: "vault_export_database"
        case .markdownParse: "markdown_parse"
        case .markdownStyle: "markdown_style"
        case .syncPerform: "sync_perform"
        }
    }

    private static let log = OSLog(subsystem: "name.aks.mde", category: "Performance")

    @discardableResult
    static func measure<T>(_ signpost: PerformanceSignpost, _ work: () throws -> T) rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: signpost.name, signpostID: id)
        defer { os_signpost(.end, log: log, name: signpost.name, signpostID: id) }
        return try work()
    }

    @discardableResult
    static func measure<T>(_ signpost: PerformanceSignpost, _ work: () async throws -> T) async rethrows -> T {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: signpost.name, signpostID: id)
        defer { os_signpost(.end, log: log, name: signpost.name, signpostID: id) }
        return try await work()
    }

    static func elapsedMS(_ work: () throws -> Void) rethrows -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try work()
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }

    static func elapsedMS(_ work: () async throws -> Void) async rethrows -> Double {
        let start = CFAbsoluteTimeGetCurrent()
        try await work()
        return (CFAbsoluteTimeGetCurrent() - start) * 1_000
    }
}
