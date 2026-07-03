//
//  MarkdownStyler.swift
//  MDE
//

import AppKit
import Markdown

enum MarkdownStyler {
    private static let baseFontSize: CGFloat = 15
    private static let tokenHiddenAlpha: CGFloat = 0.15
    private static let accent = NSColor.controlAccentColor

    static func apply(to textStorage: NSTextStorage, text: String, caretLocation: Int) {
        let length = (text as NSString).length
        guard length > 0 else { return }

        let baseFont = NSFont.systemFont(ofSize: baseFontSize)
        let baseRange = NSRange(location: 0, length: length)
        let constructs = MarkdownConstructScanner.constructs(in: text)
        let active = MarkdownConstructScanner.constructContaining(location: caretLocation, in: constructs)

        textStorage.beginEditing()
        textStorage.setAttributes([
            .font: baseFont,
            .foregroundColor: NSColor.labelColor,
        ], range: baseRange)

        styleLines(in: text, storage: textStorage)
        styleInline(in: text, storage: textStorage)
        applyHybridTokens(constructs: constructs, active: active, storage: textStorage, text: text, caretLocation: caretLocation)

        _ = Document(parsing: text)

        textStorage.endEditing()
    }

    private static func applyHybridTokens(
        constructs: [MarkdownConstruct],
        active: MarkdownConstruct?,
        storage: NSTextStorage,
        text: String,
        caretLocation: Int
    ) {
        for construct in constructs {
            let isActive = active?.fullRange == construct.fullRange

            for tokenRange in construct.tokenRanges {
                let alpha: CGFloat = isActive ? 1.0 : tokenHiddenAlpha
                storage.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(alpha), range: tokenRange)
            }

            switch construct.kind {
            case .wikilink:
                if let contentRange = construct.contentRange, !isActive {
                    storage.addAttributes([
                        .foregroundColor: accent,
                        .underlineStyle: NSUnderlineStyle.single.rawValue,
                    ], range: contentRange)
                }
            case .tag:
                if let contentRange = construct.contentRange {
                    let alpha: CGFloat = isActive ? 1.0 : 0.85
                    storage.addAttribute(.foregroundColor, value: accent.withAlphaComponent(alpha), range: contentRange)
                }
            case .task:
                if let tokenRange = construct.tokenRanges.first {
                    storage.addAttribute(.foregroundColor, value: NSColor.labelColor.withAlphaComponent(isActive ? 1.0 : tokenHiddenAlpha), range: tokenRange)
                }
            default:
                break
            }
        }
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
