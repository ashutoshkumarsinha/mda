//
//  PlatformMarkdownEditor.swift
//  MDE
//

import SwiftUI

struct PlatformMarkdownEditor: View {
    @Binding var text: String
    var resolvedLinkTitles: Set<String>
    var baseFontSize: CGFloat
    var reduceMotion: Bool
    var noteTitle: String
    var imageURLForPath: (String) -> URL?
    var onTextChange: (String) -> Void
    var onWikiLinkClick: (String) -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            #if os(macOS)
            MarkdownTextView(
                text: $text,
                resolvedLinkTitles: resolvedLinkTitles,
                baseFontSize: baseFontSize,
                reduceMotion: reduceMotion,
                noteTitle: noteTitle,
                imageURLForPath: imageURLForPath,
                onTextChange: onTextChange,
                onWikiLinkClick: onWikiLinkClick
            )
            #else
            MarkdownUITextView(
                text: $text,
                resolvedLinkTitles: resolvedLinkTitles,
                baseFontSize: baseFontSize,
                reduceMotion: reduceMotion,
                noteTitle: noteTitle,
                imageURLForPath: imageURLForPath,
                onTextChange: onTextChange,
                onWikiLinkClick: onWikiLinkClick
            )
            #endif

            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text("Start writing…")
                    .font(.system(size: baseFontSize))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 18)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
        }
    }
}
