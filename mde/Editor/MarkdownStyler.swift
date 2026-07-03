//
//  MarkdownStyler.swift
//  MDE
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

struct MarkdownStyleOptions {
    var baseFontSize: CGFloat = 15
    var reduceMotion: Bool = false
    var suspendTokenHide: Bool = false

    var tokenHiddenAlpha: CGFloat {
        if suspendTokenHide { return 1.0 }
        return reduceMotion ? 1.0 : 0.15
    }
}

enum MarkdownStyler {
    private static let accent = EditorPlatform.linkColor

    static func apply(
        to storage: NSMutableAttributedString,
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        options: MarkdownStyleOptions = MarkdownStyleOptions()
    ) {
        PerformanceSignpost.measure(.markdownStyle) {
            applyStyling(
                to: storage,
                text: text,
                caretLocation: caretLocation,
                constructs: constructs,
                options: options
            )
        }
    }

    private static func applyStyling(
        to storage: NSMutableAttributedString,
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        options: MarkdownStyleOptions
    ) {
        let length = (text as NSString).length
        guard length > 0 else { return }

        let baseFont = EditorPlatform.systemFont(ofSize: options.baseFontSize)
        let baseRange = NSRange(location: 0, length: length)
        let active = MarkdownConstructScanner.constructContaining(location: caretLocation, in: constructs)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: EditorPlatform.labelColor,
        ], range: baseRange)

        styleLines(in: text, storage: storage, options: options)
        styleInline(in: text, storage: storage, options: options)
        applyHybridTokens(
            constructs: constructs,
            active: active,
            storage: storage,
            options: options
        )
        storage.endEditing()
    }

    private static func applyHybridTokens(
        constructs: [MarkdownConstruct],
        active: MarkdownConstruct?,
        storage: NSMutableAttributedString,
        options: MarkdownStyleOptions
    ) {
        let tokenHiddenAlpha = options.tokenHiddenAlpha

        for construct in constructs {
            let isActive = active?.fullRange == construct.fullRange

            for tokenRange in construct.tokenRanges {
                let alpha: CGFloat = isActive ? 1.0 : tokenHiddenAlpha
                storage.addAttribute(
                    .foregroundColor,
                    value: EditorPlatform.labelColor.withAlphaComponent(alpha),
                    range: tokenRange
                )
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
                    storage.addAttribute(
                        .foregroundColor,
                        value: accent.withAlphaComponent(alpha),
                        range: contentRange
                    )
                }
            case .task:
                if let tokenRange = construct.tokenRanges.first {
                    storage.addAttribute(
                        .foregroundColor,
                        value: EditorPlatform.labelColor.withAlphaComponent(isActive ? 1.0 : tokenHiddenAlpha),
                        range: tokenRange
                    )
                }
            default:
                break
            }
        }
    }

    private static func styleLines(in text: String, storage: NSMutableAttributedString, options: MarkdownStyleOptions) {
        let nsText = text as NSString
        var location = 0
        for line in text.components(separatedBy: "\n") {
            let range = NSRange(location: location, length: (line as NSString).length)
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("#") {
                let level = trimmed.prefix(while: { $0 == "#" }).count
                let size = EditorTypography.headingSize(level: level, baseSize: options.baseFontSize)
                storage.addAttributes([
                    .font: EditorPlatform.boldSystemFont(ofSize: size),
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

    private static func styleInline(in text: String, storage: NSMutableAttributedString, options: MarkdownStyleOptions) {
        let baseFontSize = options.baseFontSize
        applyPattern(#"\*\*([^*]+)\*\*"#, in: text, storage: storage) { range in
            storage.addAttribute(.font, value: EditorPlatform.boldSystemFont(ofSize: baseFontSize), range: range)
        }
        applyPattern(#"(?<!\*)\*([^*]+)\*(?!\*)"#, in: text, storage: storage) { range in
            storage.addAttribute(
                .font,
                value: EditorPlatform.italicSystemFont(ofSize: baseFontSize),
                range: range
            )
        }
        applyPattern(#"`([^`]+)`"#, in: text, storage: storage) { range in
            storage.addAttribute(
                .font,
                value: EditorPlatform.monospacedSystemFont(ofSize: baseFontSize - 1),
                range: range
            )
        }
    }

    private static func applyPattern(
        _ pattern: String,
        in text: String,
        storage: NSMutableAttributedString,
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

#if canImport(AppKit)
import AppKit

extension MarkdownStyler {
    static func apply(
        to textStorage: NSTextStorage,
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        options: MarkdownStyleOptions = MarkdownStyleOptions()
    ) {
        apply(to: textStorage as NSMutableAttributedString, text: text, caretLocation: caretLocation, constructs: constructs, options: options)
    }
}
#endif
