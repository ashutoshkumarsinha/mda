//
//  VaultGlanceStore.swift
//  MDE
//

import Foundation

/// Shared snapshot for widgets, watch complications, and glance UI.
enum VaultGlanceStore {
    static let appGroupID = "group.name.aks.mde"

    struct Snapshot: Codable, Equatable, Sendable {
        var vaultID: String
        var dailyNoteTitle: String
        var dailyNoteSnippet: String
        var updatedAt: Date
    }

    private static let snapshotKey = "mde.glance.snapshot"

    static func writeDailyNote(vaultID: String, title: String, snippet: String) {
        let snapshot = Snapshot(
            vaultID: vaultID,
            dailyNoteTitle: title,
            dailyNoteSnippet: snippet,
            updatedAt: Date()
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults?.set(data, forKey: snapshotKey)
    }

    static func readSnapshot() -> Snapshot? {
        guard let data = defaults?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }

    static var pendingShareText: String? {
        get { defaults?.string(forKey: "mde.pendingShareText") }
        set {
            if let newValue {
                defaults?.set(newValue, forKey: "mde.pendingShareText")
            } else {
                defaults?.removeObject(forKey: "mde.pendingShareText")
            }
        }
    }

    private static var defaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID) ?? .standard
    }
}
