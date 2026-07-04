//
//  MarkdownUITextView.swift
//  MDE
//

#if os(iOS)
import SwiftUI
import UIKit

private final class PlainTextPasteUITextView: UITextView {
    override func paste(_ sender: Any?) {
        guard let string = UIPasteboard.general.string else {
            super.paste(sender)
            return
        }
        insertText(string)
    }
}

struct MarkdownUITextView: UIViewRepresentable {
    @Binding var text: String
    var resolvedLinkTitles: Set<String>
    var baseFontSize: CGFloat
    var reduceMotion: Bool
    var noteTitle: String
    var imageURLForPath: (String) -> URL?
    var onTextChange: (String) -> Void
    var onWikiLinkClick: (String) -> Void

    func makeUIView(context: Context) -> UITextView {
        let textView = PlainTextPasteUITextView()
        textView.delegate = context.coordinator
        textView.font = .systemFont(ofSize: baseFontSize)
        textView.text = text
        textView.backgroundColor = .systemBackground
        textView.textContainerInset = UIEdgeInsets(top: 16, left: 12, bottom: 16, right: 12)
        textView.isScrollEnabled = true
        textView.alwaysBounceVertical = true
        textView.autocorrectionType = .yes
        textView.smartDashesType = .no
        textView.smartQuotesType = .no

        configureAccessibility(on: textView)

        context.coordinator.textView = textView
        context.coordinator.styleController.styleOptions = styleOptions
        context.coordinator.installTapGesture(on: textView)
        context.coordinator.applyStyles(fullDocument: true)

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.resolvedLinkTitles = resolvedLinkTitles
        context.coordinator.imageURLForPath = imageURLForPath
        context.coordinator.styleController.styleOptions = styleOptions
        textView.font = .systemFont(ofSize: baseFontSize)
        configureAccessibility(on: textView)
        if MarkdownImageSerialization.plaintext(from: textView.attributedText) != text {
            let selected = textView.selectedRange
            textView.text = text
            textView.selectedRange = selected
            context.coordinator.applyStyles(fullDocument: true)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            resolvedLinkTitles: resolvedLinkTitles,
            styleOptions: styleOptions,
            onTextChange: onTextChange,
            onWikiLinkClick: onWikiLinkClick,
            imageURLForPath: imageURLForPath
        )
    }

    private var styleOptions: MarkdownStyleOptions {
        MarkdownStyleOptions(
            baseFontSize: baseFontSize,
            reduceMotion: reduceMotion,
            imageURLForPath: imageURLForPath
        )
    }

    private func configureAccessibility(on textView: UITextView) {
        textView.accessibilityLabel = AccessibilityLabels.editorPlaceholder(noteTitle: noteTitle)
        textView.accessibilityHint = "Markdown note editor"
        textView.accessibilityIdentifier = "note-editor"
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var resolvedLinkTitles: Set<String>
        let styleController = MarkdownEditorStyleController()
        var imageURLForPath: (String) -> URL?
        var onTextChange: (String) -> Void
        var onWikiLinkClick: (String) -> Void
        weak var textView: UITextView?

        init(
            text: Binding<String>,
            resolvedLinkTitles: Set<String>,
            styleOptions: MarkdownStyleOptions,
            onTextChange: @escaping (String) -> Void,
            onWikiLinkClick: @escaping (String) -> Void,
            imageURLForPath: @escaping (String) -> URL?
        ) {
            _text = text
            self.resolvedLinkTitles = resolvedLinkTitles
            self.imageURLForPath = imageURLForPath
            self.onTextChange = onTextChange
            self.onWikiLinkClick = onWikiLinkClick
            super.init()
            styleController.styleOptions = styleOptions
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !styleController.isStyleApplicationInProgress else { return }
            let updated = MarkdownImageSerialization.plaintext(from: textView.attributedText)
            text = updated
            onTextChange(updated)
            scheduleStyleApply()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            scheduleStyleApply()
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText replacement: String) -> Bool {
            guard let expanded = MarkdownEditorLogic.expandedDeletionRange(
                for: range,
                replacement: replacement,
                in: textView.text
            ) else {
                return true
            }
            styleController.noteStyleApplicationBegan()
            let updated = (textView.text as NSString).replacingCharacters(in: expanded, with: "")
            textView.text = updated
            text = updated
            onTextChange(updated)
            styleController.noteStyleApplicationEnded()
            refreshAfterTextMutation(updated, caret: expanded.location)
            return false
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)

            if let toggled = MarkdownEditorLogic.toggleTask(at: index, in: textView.text) {
                styleController.noteStyleApplicationBegan()
                textView.text = toggled
                text = toggled
                onTextChange(toggled)
                styleController.noteStyleApplicationEnded()
                refreshAfterTextMutation(toggled, caret: index)
                return
            }

            if let title = MarkdownEditorLogic.wikiLinkTitle(at: index, in: textView.text) {
                onWikiLinkClick(title)
                return
            }

            if let url = MarkdownEditorLogic.externalLinkURL(at: index, in: textView.text) {
                EditorPlatform.openURL(url)
            }
        }

        func applyStyles(
            constructs: [MarkdownConstruct]? = nil,
            styleRange: NSRange? = nil,
            fullDocument: Bool = false
        ) {
            guard let textView else { return }
            let storage = textView.textStorage
            if fullDocument, constructs == nil, styleController.cachedConstructs.isEmpty {
                Task {
                    await styleController.parseAndApply(
                        text: text,
                        caretLocation: textView.selectedRange.location,
                        fullDocument: true
                    ) { parsed, _ in
                        self.applyStyles(constructs: parsed, fullDocument: true)
                    }
                }
                return
            }

            styleController.noteStyleApplicationBegan()
            defer { styleController.noteStyleApplicationEnded() }

            let caret = textView.selectedRange.location
            let markdown = text
            if MarkdownImageSerialization.plaintext(from: storage) != markdown {
                let selected = textView.selectedRange
                storage.replaceCharacters(in: NSRange(location: 0, length: storage.length), with: markdown)
                textView.selectedRange = selected
            }

            var options = styleController.styleOptions
            options.imageURLForPath = imageURLForPath
            options.suspendTokenHide = textView.markedTextRange != nil

            let activeConstructs = constructs ?? styleController.cachedConstructs
            let range = fullDocument
                ? nil
                : (styleRange ?? MarkdownLineIndex.stylingNeighborhood(in: markdown, caretLocation: caret))

            MarkdownStyler.apply(
                to: storage,
                text: markdown,
                caretLocation: caret,
                constructs: activeConstructs,
                options: options,
                styleRange: range
            )
        }

        private func scheduleStyleApply() {
            guard let textView else { return }
            let caret = textView.selectedRange.location
            let content = text

            styleController.scheduleStyleApply(text: content, caretLocation: caret) { constructs, styleRange in
                self.applyStyles(constructs: constructs, styleRange: styleRange)
            }
        }

        private func refreshAfterTextMutation(_ content: String, caret: Int) {
            Task {
                await styleController.parseAndApply(text: content, caretLocation: caret) { constructs, styleRange in
                    self.applyStyles(constructs: constructs, styleRange: styleRange)
                }
            }
        }

        func installTapGesture(on textView: UITextView) {
            let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
            gesture.delegate = self
            textView.addGestureRecognizer(gesture)
        }
    }
}

extension MarkdownUITextView.Coordinator: UIGestureRecognizerDelegate {
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        otherGestureRecognizer != textView?.panGestureRecognizer
    }
}
#endif
