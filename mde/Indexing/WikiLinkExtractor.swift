//
//  WikiLinkExtractor.swift
//  MDE
//

import Foundation

enum WikiLinkExtractor {
    private static let linkPattern = /\[\[([^\]]+)\]\]/

    static func extractTitles(from content: String) -> [String] {
        var titles = Set<String>()
        for match in content.matches(of: linkPattern) {
            let title = String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                titles.insert(title)
            }
        }
        return titles.sorted()
    }

    static func linkRanges(in text: String) -> [(title: String, fullRange: NSRange, titleRange: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let title = nsText.substring(with: match.range(at: 1))
            let full = match.range
            let innerStart = full.location + 2
            let innerLength = max(0, full.length - 4)
            return (title, full, NSRange(location: innerStart, length: innerLength))
        }
    }
}
