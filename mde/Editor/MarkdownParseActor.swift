//
//  MarkdownParseActor.swift
//  MDE
//

import Foundation
import Markdown

struct MarkdownParseResult: Sendable {
    let constructs: [MarkdownConstruct]
    let documentParseSucceeded: Bool
}

actor MarkdownParseActor {
    func parse(text: String) -> MarkdownParseResult {
        PerformanceSignpost.measure(.markdownParse) {
            let constructs = MarkdownConstructScanner.constructs(in: text)
            _ = Document(parsing: text)
            return MarkdownParseResult(constructs: constructs, documentParseSucceeded: true)
        }
    }
}
