import SwiftUI

struct GlanceSnapshot: Codable {
    var vaultID: String
    var dailyNoteTitle: String
    var dailyNoteSnippet: String
    var updatedAt: Date
}

enum GlanceReader {
    static let appGroupID = "group.name.aks.mde"
    private static let snapshotKey = "mde.glance.snapshot"

    static func load() -> GlanceSnapshot? {
        guard let data = UserDefaults(suiteName: appGroupID)?.data(forKey: snapshotKey),
              let snapshot = try? JSONDecoder().decode(GlanceSnapshot.self, from: data) else {
            return nil
        }
        return snapshot
    }
}

@main
struct MDEWatchApp: App {
    var body: some Scene {
        WindowGroup {
            WatchGlanceView()
        }
    }
}

struct WatchGlanceView: View {
    private var snapshot: GlanceSnapshot? { GlanceReader.load() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(snapshot?.dailyNoteTitle ?? "MDE")
                .font(.headline)
            Text(snapshot?.dailyNoteSnippet ?? "Open MDE on iPhone to update today's note.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding()
    }
}
