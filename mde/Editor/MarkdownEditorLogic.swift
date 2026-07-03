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
}
