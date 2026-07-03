//
//  MarkdownParseActor.swift
//  MDE
//

import Foundation

struct MarkdownParseResult: Sendable {
    let constructs: [MarkdownConstruct]
    let documentParseSucceeded: Bool
    let styleRange: NSRange
    let cacheHit: Bool
}

actor MarkdownParseActor {
    private var cachedTextHash: Int?
    private var cachedConstructs: [MarkdownConstruct] = []

    func parse(text: String, caretLocation: Int = 0) -> MarkdownParseResult {
        PerformanceSignpost.measure(.markdownParse) {
            let styleRange = MarkdownLineIndex.stylingNeighborhood(in: text, caretLocation: caretLocation)
            let textHash = text.hashValue

            if textHash == cachedTextHash {
                return MarkdownParseResult(
                    constructs: cachedConstructs,
                    documentParseSucceeded: true,
                    styleRange: styleRange,
                    cacheHit: true
                )
            }

            let constructs = MarkdownConstructScanner.constructs(in: text)
            cachedTextHash = textHash
            cachedConstructs = constructs

            return MarkdownParseResult(
                constructs: constructs,
                documentParseSucceeded: !constructs.isEmpty || text.isEmpty,
                styleRange: styleRange,
                cacheHit: false
            )
        }
    }

    /// Phase 0 compatibility — full parse without caret neighborhood.
    func parse(text: String) -> MarkdownParseResult {
        parse(text: text, caretLocation: 0)
    }
}
