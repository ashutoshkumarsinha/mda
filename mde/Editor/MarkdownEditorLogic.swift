//
//  MarkdownEditorLogic.swift
//  MDE
//

import Foundation

enum MarkdownEditorLogic {
    static func toggleTask(at index: Int, in text: String) -> String? {
        TaskListHelper.toggleTask(at: index, in: text)
    }

    static func wikiLinkTitle(at index: Int, in text: String) -> String? {
        for link in WikiLinkExtractor.linkRanges(in: text) {
            if NSLocationInRange(index, link.titleRange) || NSLocationInRange(index, link.fullRange) {
                return link.title
            }
        }
        return nil
    }

    static func externalLinkURL(at index: Int, in text: String) -> URL? {
        for ref in MarkdownLinkExtractor.references(in: text) {
            if NSLocationInRange(index, ref.fullRange) {
                let trimmed = ref.url.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let url = URL(string: trimmed), url.scheme != nil else { return nil }
                return url
            }
        }
        return nil
    }

    /// Expands a single-character deletion inside link syntax to remove the whole link token.
    static func expandedDeletionRange(for range: NSRange, replacement: String, in text: String) -> NSRange? {
        guard replacement.isEmpty else { return nil }

        for link in WikiLinkExtractor.linkRanges(in: text) {
            guard NSIntersectionRange(range, link.fullRange).length > 0 else { continue }
            if range.location <= link.fullRange.location + 1 {
                return link.fullRange
            }
        }

        for ref in MarkdownLinkExtractor.references(in: text) {
            guard NSIntersectionRange(range, ref.fullRange).length > 0 else { continue }
            if range.location <= ref.fullRange.location + 1 {
                return ref.fullRange
            }
        }

        return nil
    }
}
