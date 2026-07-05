//
//  NotionHtmlConverter.swift
//  MDE
//

import Foundation

/// Converts basic Notion HTML export pages to Markdown.
enum NotionHtmlConverter {
    static func markdown(from html: String) -> String {
        var text = html
        text = replace(#"(?is)<h1[^>]*>(.*?)</h1>"#, in: text, template: "# $1\n\n")
        text = replace(#"(?is)<h2[^>]*>(.*?)</h2>"#, in: text, template: "## $1\n\n")
        text = replace(#"(?is)<h3[^>]*>(.*?)</h3>"#, in: text, template: "### $1\n\n")
        text = replace(#"(?is)<strong[^>]*>(.*?)</strong>"#, in: text, template: "**$1**")
        text = replace(#"(?is)<b[^>]*>(.*?)</b>"#, in: text, template: "**$1**")
        text = replace(#"(?is)<em[^>]*>(.*?)</em>"#, in: text, template: "*$1*")
        text = replace(#"(?is)<i[^>]*>(.*?)</i>"#, in: text, template: "*$1*")
        text = replace(#"(?is)<a[^>]*href="([^"]+)"[^>]*>(.*?)</a>"#, in: text, template: "[$2]($1)")
        text = replace(#"(?is)<img[^>]*src="([^"]+)"[^>]*alt="([^"]*)"[^>]*/?>"#, in: text, template: "![$2]($1)")
        text = replace(#"(?is)<img[^>]*src="([^"]+)"[^>]*/?>"#, in: text, template: "![]($1)")
        text = replace(#"(?is)<li[^>]*>(.*?)</li>"#, in: text, template: "- $1\n")
        text = replace(#"(?is)<p[^>]*>(.*?)</p>"#, in: text, template: "$1\n\n")
        text = replace(#"(?is)<br\s*/?>"#, in: text, template: "\n")
        text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        text = decodeEntities(text)
        return text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func replace(_ pattern: String, in text: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: template)
    }

    private static func decodeEntities(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}
