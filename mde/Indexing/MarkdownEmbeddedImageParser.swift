//
//  MarkdownEmbeddedImageParser.swift
//  MDE
//

import Foundation

struct MarkdownEmbeddedImageReference: Equatable {
    var alt: String
    var target: String
    var fullRange: NSRange
}

enum MarkdownEmbeddedImageParser {
    private static let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#

    static func externalReferences(in text: String) -> [MarkdownEmbeddedImageReference] {
        guard let regex = try? NSRegularExpression(pattern: imagePattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let target = nsText.substring(with: match.range(at: 2)).trimmingCharacters(in: .whitespacesAndNewlines)
            guard isExternalTarget(target) else { return nil }
            return MarkdownEmbeddedImageReference(
                alt: nsText.substring(with: match.range(at: 1)),
                target: target,
                fullRange: match.range
            )
        }
    }

    private static func isExternalTarget(_ target: String) -> Bool {
        let lower = target.lowercased()
        if lower.hasPrefix("assets/") { return false }
        if lower.hasPrefix("http://") || lower.hasPrefix("https://") { return false }
        if lower.hasPrefix("data:") { return false }
        return true
    }
}
