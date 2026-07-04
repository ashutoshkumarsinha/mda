//
//  MarkdownLinkExtractor.swift
//  MDE
//

import Foundation

enum MarkdownLinkExtractor {
    struct Reference: Equatable {
        var label: String
        var url: String
        var fullRange: NSRange
        var labelRange: NSRange
        var urlRange: NSRange
    }

    static func references(in text: String) -> [Reference] {
        guard let regex = try? NSRegularExpression(pattern: #"\[([^\]]*)\]\(([^)]+)\)"#) else { return [] }
        let nsText = text as NSString
        var results: [Reference] = []
        for match in regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)) {
            guard match.numberOfRanges > 2 else { continue }
            let full = match.range
            if full.location > 0, nsText.character(at: full.location - 1) == 33 { continue }

            let labelRange = match.range(at: 1)
            let urlRange = match.range(at: 2)
            results.append(Reference(
                label: nsText.substring(with: labelRange),
                url: nsText.substring(with: urlRange),
                fullRange: full,
                labelRange: labelRange,
                urlRange: urlRange
            ))
        }
        return results
    }
}
