//
//  TagExtractor.swift
//  MDE
//

import Foundation

enum TagExtractor {
    private static let tagPattern = /#([A-Za-z0-9_-]+(?:\/[A-Za-z0-9_-]+)*)/

    static func extractPaths(from content: String) -> [String] {
        let searchable = stripInlineCode(from: content)
        var paths = Set<String>()

        for match in searchable.matches(of: tagPattern) {
            let start = match.range.lowerBound
            let end = match.range.upperBound

            if start > searchable.startIndex {
                let before = searchable[searchable.index(before: start)]
                if isTagCharacter(before) { continue }
            }
            if end < searchable.endIndex {
                let after = searchable[end]
                if isTagCharacter(after) { continue }
            }

            let path = String(match.1)
            let depth = path.split(separator: "/").count
            guard depth <= 8 else { continue }
            paths.insert(path)
        }

        return paths.sorted()
    }

    private static func isTagCharacter(_ char: Character) -> Bool {
        char.isLetter || char.isNumber || char == "_" || char == "-"
    }

    private static func stripInlineCode(from text: String) -> String {
        var result = ""
        var index = text.startIndex
        var inCode = false

        while index < text.endIndex {
            let char = text[index]
            if char == "`" {
                inCode.toggle()
                index = text.index(after: index)
                continue
            }
            if !inCode {
                result.append(char)
            }
            index = text.index(after: index)
        }

        return result
    }
}
