//
//  EditorPlatform.swift
//  MDE
//

import Foundation

#if canImport(AppKit)
import AppKit

enum EditorPlatform {
    typealias Color = NSColor
    typealias Font = NSFont

    static var labelColor: Color { .labelColor }
    static var secondaryLabelColor: Color { .secondaryLabelColor }
    static var quaternaryLabelColor: Color { .quaternaryLabelColor }
    static var linkColor: Color { .linkColor }
    static var textBackgroundColor: Color { .textBackgroundColor }

    static func systemFont(ofSize size: CGFloat) -> Font {
        .systemFont(ofSize: size)
    }

    static func boldSystemFont(ofSize size: CGFloat) -> Font {
        .boldSystemFont(ofSize: size)
    }

    static func monospacedSystemFont(ofSize size: CGFloat) -> Font {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func italicSystemFont(ofSize size: CGFloat) -> Font {
        let base = NSFont.systemFont(ofSize: size)
        return NSFontManager.shared.convert(base, toHaveTrait: .italicFontMask)
    }
}

#elseif canImport(UIKit)
import UIKit

enum EditorPlatform {
    typealias Color = UIColor
    typealias Font = UIFont

    static var labelColor: Color { .label }
    static var secondaryLabelColor: Color { .secondaryLabel }
    static var quaternaryLabelColor: Color { .quaternaryLabel }
    static var linkColor: Color { .link }
    static var textBackgroundColor: Color { .systemBackground }

    static func systemFont(ofSize size: CGFloat) -> Font {
        .systemFont(ofSize: size)
    }

    static func boldSystemFont(ofSize size: CGFloat) -> Font {
        .boldSystemFont(ofSize: size)
    }

    static func monospacedSystemFont(ofSize size: CGFloat) -> Font {
        .monospacedSystemFont(ofSize: size, weight: .regular)
    }

    static func italicSystemFont(ofSize size: CGFloat) -> Font {
        let base = UIFont.systemFont(ofSize: size)
        if let descriptor = base.fontDescriptor.withSymbolicTraits(.traitItalic) {
            return UIFont(descriptor: descriptor, size: size)
        }
        return base
    }
}
#endif
