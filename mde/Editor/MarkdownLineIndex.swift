//
//  MarkdownLineIndex.swift
//  MDE
//

import Foundation

enum MarkdownLineIndex {
    /// Line index (0-based) containing `location`.
    static func lineIndex(containing location: Int, in text: String) -> Int {
        let ns = text as NSString
        guard ns.length > 0 else { return 0 }
        let safe = min(max(0, location), ns.length - 1)
        let prefix = ns.substring(to: safe)
        return prefix.filter { $0 == "\n" }.count
    }

    /// Single-line range containing `location` (includes trailing newline when present).
    static func lineRange(containing location: Int, in text: String) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let safe = min(max(0, location), ns.length - 1)
        return ns.lineRange(for: NSRange(location: safe, length: 0))
    }

    /// Caret line ± `paddingLines` for incremental styling.
    static func stylingNeighborhood(
        in text: String,
        caretLocation: Int,
        paddingLines: Int = 1
    ) -> NSRange {
        let ns = text as NSString
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }

        let anchor = min(max(0, caretLocation), ns.length - 1)
        var range = ns.lineRange(for: NSRange(location: anchor, length: 0))

        for _ in 0..<paddingLines where range.location > 0 {
            let previous = ns.lineRange(for: NSRange(location: range.location - 1, length: 0))
            range = NSRange(location: previous.location, length: range.upperBound - previous.location)
        }

        for _ in 0..<paddingLines where range.upperBound < ns.length {
            let next = ns.lineRange(for: NSRange(location: range.upperBound, length: 0))
            range = NSRange(location: range.location, length: next.upperBound - range.location)
        }

        return range
    }
}
