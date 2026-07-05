//
//  DailyNoteHelper.swift
//  MDE
//

import Foundation

enum DailyNoteHelper {
    private static let titleFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    static func title(for date: Date = Date()) -> String {
        titleFormatter.string(from: date)
    }

    static func isDailyNoteTitle(_ title: String) -> Bool {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil
    }

    static func defaultContent(for date: Date = Date()) -> String {
        let heading = title(for: date)
        return """
        # \(heading)

        ## Focus

        -

        ## Log

        -
        """
    }

    static func parseDate(from title: String) -> Date? {
        guard isDailyNoteTitle(title) else { return nil }
        return titleFormatter.date(from: title.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}
