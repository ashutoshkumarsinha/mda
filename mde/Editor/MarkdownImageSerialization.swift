//
//  MarkdownImageSerialization.swift
//  MDE
//

import Foundation

extension NSAttributedString.Key {
    static let mdeMarkdownSource = NSAttributedString.Key("mde.markdownSource")
}

enum MarkdownImageSerialization {
    /// Reconstructs markdown from attributed text that may contain image attachment placeholders.
    static func plaintext(from attributed: NSAttributedString) -> String {
        let ns = attributed.string as NSString
        guard attributed.length > 0 else { return "" }

        var result = ""
        var index = 0
        while index < attributed.length {
            var effective = NSRange(location: 0, length: 0)
            let attrs = attributed.attributes(at: index, effectiveRange: &effective)
            if let source = attrs[.mdeMarkdownSource] as? String {
                result += source
            } else {
                result += ns.substring(with: effective)
            }
            index = effective.upperBound
        }
        return result
    }
}
