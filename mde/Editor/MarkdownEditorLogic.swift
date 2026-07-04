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
}
