//
//  TitleDeriver.swift
//  MDE
//

import Foundation

enum TitleDeriver {
    static func derive(from content: String, existingTitles: [String], excludingNoteID: String? = nil) -> String {
        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return uniqueUntitled(existingTitles: existingTitles, excludingNoteID: excludingNoteID)
        }

        let lines = trimmed.components(separatedBy: .newlines)
        for line in lines {
            let lineTrimmed = line.trimmingCharacters(in: .whitespaces)
            if lineTrimmed.hasPrefix("#") {
                let heading = lineTrimmed.drop(while: { $0 == "#" || $0 == " " })
                let title = String(heading).trimmingCharacters(in: .whitespaces)
                if !title.isEmpty {
                    return title
                }
            }
        }

        if let firstLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            let plain = stripInlineMarkdown(from: firstLine)
            if !plain.isEmpty {
                return plain
            }
        }

        return uniqueUntitled(existingTitles: existingTitles, excludingNoteID: excludingNoteID)
    }

    static func stripInlineMarkdown(from line: String) -> String {
        var text = line
        text = text.replacingOccurrences(of: #"\*\*([^*]+)\*\*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"\*([^*]+)\*"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"`([^`]+)`"#, with: "$1", options: .regularExpression)
        text = text.replacingOccurrences(of: #"#([A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)"#, with: "", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespaces)
    }

    private static func uniqueUntitled(existingTitles: [String], excludingNoteID: String?) -> String {
        let lowered = Set(existingTitles.map { $0.lowercased() })
        if !lowered.contains("untitled") {
            return "Untitled"
        }
        var index = 2
        while lowered.contains("untitled (\(index))") {
            index += 1
        }
        return "Untitled (\(index))"
    }
}
