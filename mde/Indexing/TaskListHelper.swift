//
//  TaskListHelper.swift
//  MDE
//

import Foundation

enum TaskListHelper {
    private static let taskPattern = /^(\s*[-*]\s+)\[([ xX])\](\s*)/

    static func toggleTask(at characterIndex: Int, in text: String) -> String? {
        let nsText = text as NSString
        let lineRange = nsText.lineRange(for: NSRange(location: characterIndex, length: 0))
        let line = nsText.substring(with: lineRange)

        guard let regex = try? NSRegularExpression(pattern: #"^(\s*[-*]\s+)\[([ xX])\](\s*)"#),
              let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: (line as NSString).length)) else {
            return nil
        }

        let lineNSString = line as NSString
        let marker = lineNSString.substring(with: match.range(at: 2))
        let replacement = marker.lowercased() == "x" ? " " : "x"
        let newLine = lineNSString.replacingCharacters(in: match.range(at: 2), with: replacement)

        return nsText.replacingCharacters(in: lineRange, with: newLine)
    }

    static func taskLineRanges(in text: String) -> [NSRange] {
        var ranges: [NSRange] = []
        let nsText = text as NSString
        var location = 0

        for line in text.components(separatedBy: "\n") {
            let lineRange = NSRange(location: location, length: (line as NSString).length)
            if line.range(of: #"^\s*[-*]\s+\[[ xX]\]"#, options: .regularExpression) != nil {
                ranges.append(lineRange)
            }
            location += (line as NSString).length + 1
            if location > nsText.length { break }
        }
        return ranges
    }
}
