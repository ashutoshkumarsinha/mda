//
//  MarkdownImageExtractor.swift
//  MDE
//

import Foundation

struct MarkdownImageReference: Equatable {
    var alt: String
    var assetFilename: String
    var fullRange: NSRange
    var altRange: NSRange
    var pathRange: NSRange
}

enum MarkdownImageExtractor {
    private static let imagePattern = #"!\[([^\]]*)\]\(([^)]+)\)"#

    static func references(in text: String) -> [MarkdownImageReference] {
        guard let regex = try? NSRegularExpression(pattern: imagePattern) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard match.numberOfRanges > 2 else { return nil }
            let path = nsText.substring(with: match.range(at: 2))
            guard let filename = VaultAssetStore.parseVaultAssetPath(path) else { return nil }
            return MarkdownImageReference(
                alt: nsText.substring(with: match.range(at: 1)),
                assetFilename: filename,
                fullRange: match.range,
                altRange: match.range(at: 1),
                pathRange: match.range(at: 2)
            )
        }
    }
}
