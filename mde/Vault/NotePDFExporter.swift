//
//  NotePDFExporter.swift
//  MDE
//

import Foundation
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

enum NotePDFExporter {
    enum Error: Swift.Error, LocalizedError {
        case renderFailed

        var errorDescription: String? {
            switch self {
            case .renderFailed:
                return "PDF export failed."
            }
        }
    }

    static func pdfData(title: String, body: String) throws -> Data {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let text: String
        if trimmedTitle.isEmpty {
            text = body
        } else if body.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("#") {
            text = body
        } else {
            text = "\(trimmedTitle)\n\n\(body)"
        }

        #if os(macOS)
        return try renderMacPDF(text: text)
        #else
        return try renderIOSPDF(text: text)
        #endif
    }

    #if os(macOS)
    private static func renderMacPDF(text: String) throws -> Data {
        let pageWidth: CGFloat = 612
        let pageHeight: CGFloat = 792
        let margin: CGFloat = 54
        let font = NSFont.systemFont(ofSize: 12)
        let lineHeight = font.ascender - font.descender + font.leading

        let printableWidth = pageWidth - margin * 2
        let lines = wrap(text: text, font: font, maxWidth: printableWidth)
        let linesPerPage = max(1, Int(floor((pageHeight - margin * 2) / lineHeight)))

        let data = NSMutableData()
        var mediaBox = CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight)
        guard let consumer = CGDataConsumer(data: data as CFMutableData),
              let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw Error.renderFailed
        }

        var lineIndex = 0
        while lineIndex < lines.count {
            context.beginPDFPage(nil)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)

            var y = pageHeight - margin - font.ascender
            let end = min(lineIndex + linesPerPage, lines.count)
            while lineIndex < end {
                let line = lines[lineIndex] as NSString
                line.draw(at: NSPoint(x: margin, y: y), withAttributes: [.font: font])
                y -= lineHeight
                lineIndex += 1
            }

            NSGraphicsContext.restoreGraphicsState()
            context.endPDFPage()
        }

        context.closePDF()
        return data as Data
    }

    private static func wrap(text: String, font: NSFont, maxWidth: CGFloat) -> [String] {
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            if paragraph.isEmpty {
                result.append("")
                continue
            }
            var remaining = paragraph as NSString
            while remaining.length > 0 {
                let range = remaining.rangeOfComposedCharacterSequences(
                    for: NSRange(location: 0, length: remaining.length)
                )
                var fit = range.length
                while fit > 0 {
                    let candidate = remaining.substring(with: NSRange(location: 0, length: fit))
                    let size = (candidate as NSString).size(withAttributes: [.font: font])
                    if size.width <= maxWidth { break }
                    fit -= 1
                }
                if fit == 0 { fit = 1 }
                result.append(remaining.substring(with: NSRange(location: 0, length: fit)))
                remaining = remaining.substring(from: fit) as NSString
            }
        }
        return result
    }
    #else
    private static func renderIOSPDF(text: String) throws -> Data {
        let pageRect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let font = UIFont.systemFont(ofSize: 12)
        let margin: CGFloat = 54
        let lineHeight = font.lineHeight
        let maxWidth = pageRect.width - margin * 2
        let lines = wrapIOS(text: text, font: font, maxWidth: maxWidth)
        let linesPerPage = max(1, Int(floor((pageRect.height - margin * 2) / lineHeight)))

        return renderer.pdfData { context in
            var lineIndex = 0
            while lineIndex < lines.count {
                context.beginPage()
                var y = margin + font.ascender
                let end = min(lineIndex + linesPerPage, lines.count)
                while lineIndex < end {
                    let line = lines[lineIndex]
                    (line as NSString).draw(
                        at: CGPoint(x: margin, y: y),
                        withAttributes: [.font: font]
                    )
                    y += lineHeight
                    lineIndex += 1
                }
            }
        }
    }

    private static func wrapIOS(text: String, font: UIFont, maxWidth: CGFloat) -> [String] {
        var result: [String] = []
        for paragraph in text.components(separatedBy: "\n") {
            if paragraph.isEmpty {
                result.append("")
                continue
            }
            var remaining = paragraph
            while !remaining.isEmpty {
                var fitCount = remaining.count
                while fitCount > 0 {
                    let index = remaining.index(remaining.startIndex, offsetBy: fitCount)
                    let candidate = String(remaining[..<index])
                    let width = (candidate as NSString).size(withAttributes: [.font: font]).width
                    if width <= maxWidth { break }
                    fitCount -= 1
                }
                if fitCount == 0 { fitCount = 1 }
                let index = remaining.index(remaining.startIndex, offsetBy: fitCount)
                result.append(String(remaining[..<index]))
                remaining = String(remaining[index...])
            }
        }
        return result
    }
    #endif
}
