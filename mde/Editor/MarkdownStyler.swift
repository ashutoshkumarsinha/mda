//
//  MarkdownStyler.swift
//  MDE
//

import AppKit
import Markdown

enum MarkdownStyler {
    private static let baseFontSize: CGFloat = 15

    static func apply(to textStorage: NSTextStorage, text: String) {
        let length = (text as NSString).length
        guard length > 0 else { return }

        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let baseRange = NSRange(location: 0, length: length)

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: baseRange)

        styleLines(in: text, storage: textStorage)
        styleInline(in: text, storage: textStorage)

        // swift-markdown parse validates structure; line/inline rules handle rendering for Phase 1.
        _ = Document(parsing: text)

        textStorage.endEditing()
    }

    private static func styleLines(in text: String, storage: NSTextStorage) {
        let nsText = text as NSString
        var location = 0
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(location: location, length: (line as NSString).length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let size: CGFloat = switch min(level, 6) {
                case 1: 28
                case 2: 22
                case 3: 18
                default: baseFontSize
                }
                storage.addAttributes([
                    .font: NSFont.boldSystemFont(ofSize: size),
                ], range: range)
            } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                storage.addAttributes([
                    .paragraphStyle: listParagraphStyle(),
                ], range: range)
            }

            location += (line as NSString).length + 1
            if location > nsText.length { break }
        }
    }

    private static func styleInline(in text: String, storage: NSTextStorage) {
        applyPattern(#"\*\*([^*]+)\*\*"#, in: text, storage: storage) { range in
            storage.addAttribute(.font, value: NSFont.boldSystemFont(ofSize: baseFontSize), range: range)
        }
        applyPattern(#"(?<!\*)\*([^*]+)\*(?!\*)"#, in: text, storage: storage) { range in
            let italic = NSFontManager.shared.convert(
                NSFont.systemFont(ofSize: baseFontSize),
                toHaveTrait: .italicFontMask
            )
            storage.addAttribute(.font, value: italic, range: range)
        }
        applyPattern(#"`([^`]+)`"#, in: text, storage: storage) { range in
            storage.addAttribute(
                .font,
                value: NSFont.monospacedSystemFont(ofSize: baseFontSize - 1, weight: .regular),
                range: range
            )
        }
    }

    private static func applyPattern(
        _ pattern: String,
        in text: String,
        storage: NSTextStorage,
        apply: (NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: nsText.length))
        for match in matches where match.numberOfRanges > 1 {
            apply(match.range(at: 1))
        }
    }

    private static func listParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 20
        style.firstLineHeadIndent = 8
        return style
    }
}
