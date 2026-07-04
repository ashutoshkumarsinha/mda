//
//  MarkdownConstruct.swift
//  MDE
//

import Foundation

struct MarkdownConstruct {
    enum Kind {
        case heading
        case bold
        case wikilink
        case task
        case tag
        case blockquote
        case codeFence
        case codeBlockLine
        case inlineCode
        case image
    }

    var kind: Kind
    var fullRange: NSRange
    var tokenRanges: [NSRange]
    var contentRange: NSRange?
}

enum MarkdownConstructScanner {
    static func constructs(in text: String) -> [MarkdownConstruct] {
        var result: [MarkdownConstruct] = []
        let nsText = text as NSString
        var lineLocation = 0
        var inCodeFence = false

        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            let lineRange = NSRange(location: lineLocation, length: lineLength)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                inCodeFence.toggle()
                let fenceRange = NSRange(
                    location: lineLocation + (line as NSString).range(of: trimmed).location,
                    length: (trimmed as NSString).length
                )
                result.append(MarkdownConstruct(
                    kind: .codeFence,
                    fullRange: lineRange,
                    tokenRanges: [fenceRange],
                    contentRange: nil
                ))
            } else if inCodeFence {
                result.append(MarkdownConstruct(
                    kind: .codeBlockLine,
                    fullRange: lineRange,
                    tokenRanges: [],
                    contentRange: lineRange
                ))
            } else if trimmed.hasPrefix(">") {
                let markerLength = trimmed.prefix(while: { $0 == ">" || $0.isWhitespace }).count
                let leadingSpaces = line.count - line.drop(while: { $0.isWhitespace }).count
                let tokenEnd = lineLocation + leadingSpaces + markerLength
                result.append(MarkdownConstruct(
                    kind: .blockquote,
                    fullRange: lineRange,
                    tokenRanges: [NSRange(location: lineLocation + leadingSpaces, length: markerLength)],
                    contentRange: NSRange(location: tokenEnd, length: max(0, lineRange.upperBound - tokenEnd))
                ))
            }

            if trimmed.hasPrefix("#") && !inCodeFence {
                let hashCount = trimmed.prefix(while: { $0 == "#" }).count
                let leadingSpaces = line.count - line.drop(while: { $0.isWhitespace }).count
                let tokenEnd = lineLocation + leadingSpaces + hashCount
                if hashCount < lineLength {
                    result.append(MarkdownConstruct(
                        kind: .heading,
                        fullRange: lineRange,
                        tokenRanges: [NSRange(location: lineLocation + leadingSpaces, length: hashCount)],
                        contentRange: NSRange(location: tokenEnd, length: lineRange.upperBound - tokenEnd)
                    ))
                }
            }

            if line.range(of: #"^\s*[-*]\s+\[[ xX]\]"#, options: .regularExpression) != nil, !inCodeFence {
                if let checkboxRange = checkboxTokenRange(in: line, lineLocation: lineLocation) {
                    result.append(MarkdownConstruct(
                        kind: .task,
                        fullRange: lineRange,
                        tokenRanges: [checkboxRange],
                        contentRange: nil
                    ))
                }
            }

            lineLocation += lineLength + 1
            if lineLocation > nsText.length { break }
        }

        let fenceExcluded = codeFenceExcludedRanges(in: text)
        let inlineCodes = inlineCodeConstructs(in: text, excluding: fenceExcluded)
        let literalExcluded = fenceExcluded + inlineCodes.map(\.fullRange)
        result.append(contentsOf: wikiLinkConstructs(in: text, excluding: literalExcluded))
        result.append(contentsOf: boldConstructs(in: text, excluding: literalExcluded))
        result.append(contentsOf: tagConstructs(in: text, excluding: literalExcluded))
        result.append(contentsOf: imageConstructs(in: text, excluding: literalExcluded))
        result.append(contentsOf: inlineCodes)
        return result
    }

    static func constructContaining(location: Int, in constructs: [MarkdownConstruct]) -> MarkdownConstruct? {
        constructs.first { NSLocationInRange(location, $0.fullRange) }
    }

    static func constructs(_ constructs: [MarkdownConstruct], intersecting range: NSRange) -> [MarkdownConstruct] {
        constructs.filter { NSIntersectionRange($0.fullRange, range).length > 0 }
    }

    private static func inlineCodeConstructs(in text: String, excluding: [NSRange]) -> [MarkdownConstruct] {
        guard let regex = try? NSRegularExpression(pattern: #"`([^`]+)`"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard !ranges(excluding, contain: match.range) else { return nil }
            let open = NSRange(location: match.range.location, length: 1)
            let close = NSRange(location: match.range.upperBound - 1, length: 1)
            return MarkdownConstruct(
                kind: .inlineCode,
                fullRange: match.range,
                tokenRanges: [open, close],
                contentRange: match.range(at: 1)
            )
        }
    }

    /// Fenced blocks and inline `` ` `` spans — other constructs must not match inside.
    private static func codeFenceExcludedRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        var lineLocation = 0
        var fenceStart: Int?
        let nsText = text as NSString

        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if let start = fenceStart {
                    let end = lineLocation + lineLength
                    ranges.append(NSRange(location: start, length: end - start))
                    fenceStart = nil
                } else {
                    fenceStart = lineLocation
                }
            }

            lineLocation += lineLength + 1
            if lineLocation > nsText.length { break }
        }

        if let start = fenceStart {
            ranges.append(NSRange(location: start, length: nsText.length - start))
        }
        return ranges
    }

    private static func ranges(_ ranges: [NSRange], contain target: NSRange) -> Bool {
        ranges.contains { NSIntersectionRange($0, target).length > 0 }
    }

    private static func imageConstructs(in text: String, excluding: [NSRange]) -> [MarkdownConstruct] {
        MarkdownImageExtractor.references(in: text).compactMap { ref in
            guard !ranges(excluding, contain: ref.fullRange) else { return nil }
            let openToken = NSRange(location: ref.fullRange.location, length: 2)
            let closeBracket = NSRange(location: ref.altRange.upperBound, length: 1)
            let openParen = NSRange(location: ref.pathRange.location - 1, length: 1)
            let closeParen = NSRange(location: ref.pathRange.upperBound, length: 1)
            return MarkdownConstruct(
                kind: .image,
                fullRange: ref.fullRange,
                tokenRanges: [openToken, closeBracket, openParen, closeParen],
                contentRange: ref.pathRange
            )
        }
    }

    private static func wikiLinkConstructs(in text: String, excluding: [NSRange]) -> [MarkdownConstruct] {
        WikiLinkExtractor.linkRanges(in: text).compactMap { link in
            guard !ranges(excluding, contain: link.fullRange) else { return nil }
            let open = NSRange(location: link.fullRange.location, length: 2)
            let close = NSRange(location: link.fullRange.upperBound - 2, length: 2)
            return MarkdownConstruct(
                kind: .wikilink,
                fullRange: link.fullRange,
                tokenRanges: [open, close],
                contentRange: link.titleRange
            )
        }
    }

    private static func boldConstructs(in text: String, excluding: [NSRange]) -> [MarkdownConstruct] {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard !ranges(excluding, contain: match.range) else { return nil }
            let open = NSRange(location: match.range.location, length: 2)
            let close = NSRange(location: match.range.upperBound - 2, length: 2)
            return MarkdownConstruct(
                kind: .bold,
                fullRange: match.range,
                tokenRanges: [open, close],
                contentRange: match.range(at: 1)
            )
        }
    }

    private static func tagConstructs(in text: String, excluding: [NSRange]) -> [MarkdownConstruct] {
        guard let regex = try? NSRegularExpression(pattern: #"#([A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).compactMap { match in
            guard !ranges(excluding, contain: match.range) else { return nil }
            return MarkdownConstruct(
                kind: .tag,
                fullRange: match.range,
                tokenRanges: [NSRange(location: match.range.location, length: 1)],
                contentRange: match.range(at: 1)
            )
        }
    }

    private static func checkboxTokenRange(in line: String, lineLocation: Int) -> NSRange? {
        guard let regex = try? NSRegularExpression(pattern: #"(\[[ xX]\])"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }
        return NSRange(location: lineLocation + match.range.location, length: match.range.length)
    }
}

private extension String {
    var trimLeading: Substring {
        drop(while: { $0.isWhitespace })
    }
}