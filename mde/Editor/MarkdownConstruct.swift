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

        for line in text.components(separatedBy: "\n") {
            let lineLength = (line as NSString).length
            let lineRange = NSRange(location: lineLocation, length: lineLength)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
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

            if line.range(of: #"^\s*[-*]\s+\[[ xX]\]"#, options: .regularExpression) != nil {
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

        result.append(contentsOf: wikiLinkConstructs(in: text))
        result.append(contentsOf: boldConstructs(in: text))
        result.append(contentsOf: tagConstructs(in: text))
        return result
    }

    static func constructContaining(location: Int, in constructs: [MarkdownConstruct]) -> MarkdownConstruct? {
        constructs.first { NSLocationInRange(location, $0.fullRange) }
    }

    static func constructs(_ constructs: [MarkdownConstruct], intersecting range: NSRange) -> [MarkdownConstruct] {
        constructs.filter { NSIntersectionRange($0.fullRange, range).length > 0 }
    }

    private static func wikiLinkConstructs(in text: String) -> [MarkdownConstruct] {
        WikiLinkExtractor.linkRanges(in: text).map { link in
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

    private static func boldConstructs(in text: String) -> [MarkdownConstruct] {
        guard let regex = try? NSRegularExpression(pattern: #"\*\*([^*]+)\*\*"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
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

    private static func tagConstructs(in text: String) -> [MarkdownConstruct] {
        guard let regex = try? NSRegularExpression(pattern: #"#([A-Za-z0-9_-]+(?:/[A-Za-z0-9_-]+)*)"#) else { return [] }
        let nsText = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: nsText.length)).map { match in
            MarkdownConstruct(
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