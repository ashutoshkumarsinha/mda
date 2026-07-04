//
//  WikiLinkExtractor.swift
//  MDE
//

import Foundation

enum WikiLinkExtractor {
    private static let linkPattern = /\[\[([^|\]]+)(?:\|([^\]]+))?\]\]/

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

    /// `title` is the link target; `titleRange` spans the visible label (alias when present).
    static func linkRanges(in text: String) -> [(title: String, fullRange: NSRange, titleRange: NSRange)] {
        guard let regex = try? NSRegularExpression(pattern: #"\[\[([^|\]]+)(?:\|([^\]]+))?\]\]"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            let target = nsText.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let full = match.range
            let displayRange: NSRange
            if match.numberOfRanges > 2, match.range(at: 2).location != NSNotFound, match.range(at: 2).length > 0 {
                displayRange = match.range(at: 2)
            } else {
                displayRange = match.range(at: 1)
            }
            return (target, full, displayRange)
        }
    }
}
