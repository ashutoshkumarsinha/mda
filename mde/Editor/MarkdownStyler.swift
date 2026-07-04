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
    var imageURLForPath: ((String) -> URL?)? = nil

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
        options: MarkdownStyleOptions = MarkdownStyleOptions(),
        styleRange: NSRange? = nil
    ) {
        let signpost: PerformanceSignpost = styleRange == nil ? .markdownStyle : .markdownStyleIncremental
        PerformanceSignpost.measure(signpost) {
            applyStyling(
                to: storage,
                text: text,
                caretLocation: caretLocation,
                constructs: constructs,
                options: options,
                styleRange: styleRange
            )
        }
    }

    private static func applyStyling(
        to storage: NSMutableAttributedString,
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        options: MarkdownStyleOptions,
        styleRange: NSRange?
    ) {
        let length = (text as NSString).length
        guard length > 0 else { return }

        let fullRange = NSRange(location: 0, length: length)
        let targetRange = styleRange.map { NSIntersectionRange($0, fullRange) } ?? fullRange
        guard targetRange.length > 0 else { return }

        let scopedConstructs = MarkdownConstructScanner.constructs(constructs, intersecting: targetRange)
        let baseFont = EditorPlatform.systemFont(ofSize: options.baseFontSize)
        let active = MarkdownConstructScanner.constructContaining(location: caretLocation, in: constructs)

        storage.beginEditing()
        storage.setAttributes([
            .font: baseFont,
            .foregroundColor: EditorPlatform.labelColor,
        ], range: targetRange)

        styleLines(in: text, storage: storage, options: options, styleRange: targetRange)
        styleInline(in: text, storage: storage, options: options, styleRange: targetRange)
        applyHybridTokens(
            constructs: scopedConstructs,
            active: active,
            storage: storage,
            options: options
        )
        if let imageURLForPath = options.imageURLForPath {
            MarkdownImageRenderer.apply(
                to: storage,
                text: text,
                caretLocation: caretLocation,
                constructs: constructs,
                imageURLForPath: imageURLForPath
            )
        }
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

            if construct.kind != .inlineCode {
                for tokenRange in construct.tokenRanges {
                    let alpha: CGFloat = isActive ? 1.0 : tokenHiddenAlpha
                    storage.addAttribute(
                        .foregroundColor,
                        value: EditorPlatform.labelColor.withAlphaComponent(alpha),
                        range: tokenRange
                    )
                }
            }

            switch construct.kind {
            case .inlineCode:
                for tokenRange in construct.tokenRanges {
                    storage.addAttribute(
                        .foregroundColor,
                        value: EditorPlatform.labelColor,
                        range: tokenRange
                    )
                }
                if let contentRange = construct.contentRange {
                    storage.addAttributes([
                        .font: EditorPlatform.monospacedSystemFont(ofSize: options.baseFontSize - 1),
                        .backgroundColor: EditorPlatform.quaternaryLabelColor.withAlphaComponent(0.12),
                    ], range: contentRange)
                }
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
            case .codeBlockLine:
                if let contentRange = construct.contentRange {
                    storage.addAttributes([
                        .font: EditorPlatform.monospacedSystemFont(ofSize: options.baseFontSize - 1),
                        .backgroundColor: EditorPlatform.quaternaryLabelColor.withAlphaComponent(0.15),
                    ], range: contentRange)
                }
            case .codeFence:
                if let tokenRange = construct.tokenRanges.first {
                    storage.addAttribute(
                        .font,
                        value: EditorPlatform.monospacedSystemFont(ofSize: options.baseFontSize - 1),
                        range: tokenRange
                    )
                }
            case .blockquote:
                if let contentRange = construct.contentRange, contentRange.length > 0 {
                    storage.addAttributes([
                        .foregroundColor: EditorPlatform.secondaryLabelColor,
                        .paragraphStyle: blockquoteParagraphStyle(),
                    ], range: contentRange)
                }
            case .image:
                if let contentRange = construct.contentRange {
                    storage.addAttributes([
                        .foregroundColor: accent,
                        .font: EditorPlatform.italicSystemFont(ofSize: options.baseFontSize - 1),
                    ], range: contentRange)
                }
            default:
                break
            }
        }
    }

    private static func styleLines(
        in text: String,
        storage: NSMutableAttributedString,
        options: MarkdownStyleOptions,
        styleRange: NSRange
    ) {
        let nsText = text as NSString
        guard styleRange.length > 0, nsText.length > 0 else { return }

        var lineStart = styleRange.location
        let stopAt = styleRange.upperBound

        while lineStart < stopAt && lineStart < nsText.length {
            let lineRange = nsText.lineRange(for: NSRange(location: lineStart, length: 0))
            let applyRange = NSIntersectionRange(lineRange, styleRange)
            if applyRange.length > 0 {
                let line = nsText.substring(with: lineRange).trimmingCharacters(in: .newlines)
                let trimmed = line.trimmingCharacters(in: .whitespaces)

                if trimmed.hasPrefix("#") {
                    let level = trimmed.prefix(while: { $0 == "#" }).count
                    let size = EditorTypography.headingSize(level: level, baseSize: options.baseFontSize)
                    storage.addAttributes([
                        .font: EditorPlatform.boldSystemFont(ofSize: size),
                    ], range: applyRange)
                } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                    storage.addAttributes([
                        .paragraphStyle: listParagraphStyle(),
                    ], range: applyRange)
                }
            }

            guard lineRange.upperBound > lineStart else { break }
            lineStart = lineRange.upperBound
        }
    }

    private static func styleInline(
        in text: String,
        storage: NSMutableAttributedString,
        options: MarkdownStyleOptions,
        styleRange: NSRange
    ) {
        let baseFontSize = options.baseFontSize
        applyPattern(#"\*\*([^*]+)\*\*"#, in: text, storage: storage, styleRange: styleRange) { range in
            storage.addAttribute(.font, value: EditorPlatform.boldSystemFont(ofSize: baseFontSize), range: range)
        }
        applyPattern(#"(?<!\*)\*([^*]+)\*(?!\*)"#, in: text, storage: storage, styleRange: styleRange) { range in
            storage.addAttribute(
                .font,
                value: EditorPlatform.italicSystemFont(ofSize: baseFontSize),
                range: range
            )
        }
        applyPattern(#"`([^`]+)`"#, in: text, storage: storage, styleRange: styleRange) { range in
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
        styleRange: NSRange,
        apply: (NSRange) -> Void
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
        let nsText = text as NSString
        let matches = regex.matches(in: text, range: styleRange)
        for match in matches where match.numberOfRanges > 1 {
            let contentRange = match.range(at: 1)
            if NSIntersectionRange(contentRange, styleRange).length > 0 {
                apply(contentRange)
            }
        }
    }

    private static func listParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 20
        style.firstLineHeadIndent = 8
        return style
    }

    private static func blockquoteParagraphStyle() -> NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.headIndent = 14
        style.firstLineHeadIndent = 14
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
        apply(to: textStorage as NSMutableAttributedString, text: text, caretLocation: caretLocation, constructs: constructs, options: options, styleRange: nil)
    }
}
#endif
