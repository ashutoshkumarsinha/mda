//
//  MarkdownTableParser.swift
//  MDE
//

import Foundation

struct MarkdownTableRow: Equatable {
    enum Role: Equatable {
        case header
        case separator
        case body
    }

    var role: Role
    var lineRange: NSRange
    var pipeRanges: [NSRange]
    var cellRanges: [NSRange]
}

struct MarkdownTableBlock: Equatable {
    var fullRange: NSRange
    var rows: [MarkdownTableRow]
}

enum MarkdownTableParser {
    static func blocks(in text: String) -> [MarkdownTableBlock] {
        let nsText = text as NSString
        guard nsText.length > 0 else { return [] }

        var blocks: [MarkdownTableBlock] = []
        var lineLocation = 0
        var inCodeFence = false
        var lineIndex = 0
        let lines = text.components(separatedBy: "\n")
        var tableLines: [(lineRange: NSRange, line: String)] = []

        func flushTableIfNeeded() {
            guard let block = makeBlock(from: tableLines) else {
                tableLines.removeAll()
                return
            }
            blocks.append(block)
            tableLines.removeAll()
        }

        for line in lines {
            let lineLength = (line as NSString).length
            let lineRange = NSRange(location: lineLocation, length: lineLength)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushTableIfNeeded()
                inCodeFence.toggle()
            } else if !inCodeFence {
                if isTableRowLine(line) {
                    tableLines.append((lineRange, line))
                } else {
                    flushTableIfNeeded()
                }
            } else {
                flushTableIfNeeded()
            }

            lineLocation += lineLength + 1
            lineIndex += 1
            if lineLocation > nsText.length { break }
        }

        flushTableIfNeeded()
        return blocks
    }

    static func isTableRowLine(_ line: String) -> Bool {
        line.contains("|")
    }

    static func isSeparatorRow(_ line: String) -> Bool {
        guard line.contains("|") else { return false }
        let cells = tableCells(in: line)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy(isSeparatorCell)
    }

    static func tableCells(in line: String) -> [String] {
        var trimmed = line
        if trimmed.hasPrefix("|") {
            trimmed.removeFirst()
        }
        if trimmed.hasSuffix("|") {
            trimmed.removeLast()
        }
        return trimmed.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
    }

    static func pipeRanges(in line: String, lineLocation: Int) -> [NSRange] {
        let nsLine = line as NSString
        var ranges: [NSRange] = []
        var index = 0
        while index < nsLine.length {
            let range = nsLine.range(of: "|", options: [], range: NSRange(location: index, length: nsLine.length - index))
            guard range.location != NSNotFound else { break }
            ranges.append(NSRange(location: lineLocation + range.location, length: 1))
            index = range.upperBound
        }
        return ranges
    }

    static func cellRanges(in line: String, lineLocation: Int) -> [NSRange] {
        let nsLine = line as NSString
        var ranges: [NSRange] = []
        var start = 0
        var index = 0

        while index < nsLine.length {
            let charRange = NSRange(location: index, length: 1)
            let character = nsLine.substring(with: charRange)
            if character == "|" {
                let length = index - start
                if length > 0 {
                    ranges.append(NSRange(location: lineLocation + start, length: length))
                }
                start = index + 1
            }
            index += 1
        }

        if start < nsLine.length {
            ranges.append(NSRange(location: lineLocation + start, length: nsLine.length - start))
        }

        // Drop empty leading/trailing cells from optional outer pipes.
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("|"), let first = ranges.first, first.length == 0 {
            ranges.removeFirst()
        }
        if line.trimmingCharacters(in: .whitespaces).hasSuffix("|"), let last = ranges.last, last.length == 0 {
            ranges.removeLast()
        }

        return ranges
    }

    private static func isSeparatorCell(_ cell: String) -> Bool {
        let trimmed = cell.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty, trimmed.contains("-") else { return false }
        return trimmed.allSatisfy { $0 == "-" || $0 == ":" || $0.isWhitespace }
    }

    private static func makeBlock(from lines: [(lineRange: NSRange, line: String)]) -> MarkdownTableBlock? {
        guard lines.count >= 2 else { return nil }
        guard isSeparatorRow(lines[1].line) else { return nil }

        let fullRange = NSRange(
            location: lines[0].lineRange.location,
            length: lines.last!.lineRange.upperBound - lines[0].lineRange.location
        )

        var rows: [MarkdownTableRow] = []
        for (offset, entry) in lines.enumerated() {
            let role: MarkdownTableRow.Role
            switch offset {
            case 0: role = .header
            case 1: role = .separator
            default: role = .body
            }
            rows.append(MarkdownTableRow(
                role: role,
                lineRange: entry.lineRange,
                pipeRanges: pipeRanges(in: entry.line, lineLocation: entry.lineRange.location),
                cellRanges: role == .separator ? [] : cellRanges(in: entry.line, lineLocation: entry.lineRange.location)
            ))
        }

        return MarkdownTableBlock(fullRange: fullRange, rows: rows)
    }
}
