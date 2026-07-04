//
//  MarkdownImageRenderer.swift
//  MDE
//

import Foundation

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum MarkdownImageRenderer {
    private static let maxDisplayWidth: CGFloat = 360

    static func apply(
        to storage: NSMutableAttributedString,
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        imageURLForPath: (String) -> URL?
    ) {
        let imageConstructs = constructs.filter { $0.kind == .image }
        guard !imageConstructs.isEmpty else { return }

        for construct in imageConstructs.reversed() {
            guard !NSLocationInRange(caretLocation, construct.fullRange),
                  let pathRange = construct.contentRange else { continue }

            let path = (text as NSString).substring(with: pathRange)
            guard let fileURL = imageURLForPath(path),
                  let attachment = makeAttachment(for: fileURL) else { continue }

            let original = (text as NSString).substring(with: construct.fullRange)
            let replacement = NSMutableAttributedString(attachment: attachment)
            replacement.addAttribute(.mdeMarkdownSource, value: original, range: NSRange(location: 0, length: 1))
            storage.replaceCharacters(in: construct.fullRange, with: replacement)
        }
    }

    #if os(macOS)
    private static func makeAttachment(for url: URL) -> NSTextAttachment? {
        guard let image = NSImage(contentsOf: url) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = displayBounds(for: image.size)
        return attachment
    }

    private static func displayBounds(for imageSize: NSSize) -> CGRect {
        let width = min(maxDisplayWidth, max(imageSize.width, 1))
        let scale = width / max(imageSize.width, 1)
        let height = max(imageSize.height * scale, 1)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
    #else
    private static func makeAttachment(for url: URL) -> NSTextAttachment? {
        guard let image = UIImage(contentsOfFile: url.path) else { return nil }
        let attachment = NSTextAttachment()
        attachment.image = image
        attachment.bounds = displayBounds(for: image.size)
        return attachment
    }

    private static func displayBounds(for imageSize: CGSize) -> CGRect {
        let width = min(maxDisplayWidth, max(imageSize.width, 1))
        let scale = width / max(imageSize.width, 1)
        let height = max(imageSize.height * scale, 1)
        return CGRect(x: 0, y: 0, width: width, height: height)
    }
    #endif
}
