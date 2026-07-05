import WidgetKit
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

struct MDEWidgetEntry: TimelineEntry {
    let date: Date
    let title: String
    let snippet: String
}

struct MDEWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> MDEWidgetEntry {
        MDEWidgetEntry(date: Date(), title: "Today's Note", snippet: "Open MDE to capture.")
    }

    func getSnapshot(in context: Context, completion: @escaping (MDEWidgetEntry) -> Void) {
        completion(makeEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MDEWidgetEntry>) -> Void) {
        let entry = makeEntry()
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date().addingTimeInterval(3600)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }

    private func makeEntry() -> MDEWidgetEntry {
        if let snapshot = GlanceReader.load() {
            return MDEWidgetEntry(
                date: snapshot.updatedAt,
                title: snapshot.dailyNoteTitle,
                snippet: snapshot.dailyNoteSnippet
            )
        }
        return MDEWidgetEntry(date: Date(), title: DailyNoteTitle.today, snippet: "Open MDE to start today's note.")
    }
}

enum DailyNoteTitle {
    static var today: String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

struct MDEWidgetEntryView: View {
    var entry: MDEWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("MDE", systemImage: "calendar")
                .font(.caption.weight(.semibold))
            Text(entry.title)
                .font(.headline)
            Text(entry.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}

struct MDEWidget: Widget {
    let kind = "MDEWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MDEWidgetProvider()) { entry in
            MDEWidgetEntryView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Note")
        .description("Glance at your daily note from MDE.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

@main
struct MDEWidgetBundle: WidgetBundle {
    var body: some Widget {
        MDEWidget()
    }
}
