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
        context.coordinator.styleOptions = styleOptions
        context.coordinator.installTapGesture(on: textView)
        context.coordinator.applyStyles()

        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.resolvedLinkTitles = resolvedLinkTitles
        context.coordinator.styleOptions = styleOptions
        textView.font = .systemFont(ofSize: baseFontSize)
        configureAccessibility(on: textView)
        if textView.text != text {
            let selected = textView.selectedRange
            textView.text = text
            textView.selectedRange = selected
            context.coordinator.applyStyles()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            resolvedLinkTitles: resolvedLinkTitles,
            styleOptions: styleOptions,
            onTextChange: onTextChange,
            onWikiLinkClick: onWikiLinkClick
        )
    }

    private var styleOptions: MarkdownStyleOptions {
        MarkdownStyleOptions(baseFontSize: baseFontSize, reduceMotion: reduceMotion)
    }

    private func configureAccessibility(on textView: UITextView) {
        textView.accessibilityLabel = AccessibilityLabels.editorPlaceholder(noteTitle: noteTitle)
        textView.accessibilityHint = "Markdown note editor"
        textView.accessibilityIdentifier = "note-editor"
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        @Binding var text: String
        var resolvedLinkTitles: Set<String>
        var styleOptions = MarkdownStyleOptions()
        var onTextChange: (String) -> Void
        var onWikiLinkClick: (String) -> Void
        weak var textView: UITextView?
        private var styleTask: Task<Void, Never>?
        private var isApplyingStyles = false
        private let parseActor = MarkdownParseActor()
        private var cachedConstructs: [MarkdownConstruct] = []

        init(
            text: Binding<String>,
            resolvedLinkTitles: Set<String>,
            styleOptions: MarkdownStyleOptions,
            onTextChange: @escaping (String) -> Void,
            onWikiLinkClick: @escaping (String) -> Void
        ) {
            _text = text
            self.resolvedLinkTitles = resolvedLinkTitles
            self.styleOptions = styleOptions
            self.onTextChange = onTextChange
            self.onWikiLinkClick = onWikiLinkClick
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingStyles else { return }
            let updated = textView.text ?? ""
            text = updated
            onTextChange(updated)
            scheduleStyleApply()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            scheduleStyleApply()
        }

        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let index = textView.offset(from: textView.beginningOfDocument, to: position)

            if let toggled = MarkdownEditorLogic.toggleTask(at: index, in: textView.text) {
                isApplyingStyles = true
                textView.text = toggled
                text = toggled
                onTextChange(toggled)
                isApplyingStyles = false
                applyStyles(constructs: cachedConstructs)
                return
            }

            if let title = MarkdownEditorLogic.wikiLinkTitle(at: index, in: textView.text) {
                onWikiLinkClick(title)
            }
        }

        func applyStyles(constructs: [MarkdownConstruct]? = nil) {
            guard let textView else { return }
            isApplyingStyles = true
            let caret = textView.selectedRange.location
            var options = styleOptions
            options.suspendTokenHide = textView.markedTextRange != nil
            let content = textView.text ?? ""
            let storage = NSMutableAttributedString(attributedString: textView.attributedText)
            let activeConstructs = constructs ?? cachedConstructs
            MarkdownStyler.apply(
                to: storage,
                text: content,
                caretLocation: caret,
                constructs: activeConstructs,
                options: options
            )
            let selected = textView.selectedRange
            textView.attributedText = storage
            textView.selectedRange = selected
            isApplyingStyles = false
        }

        private func scheduleStyleApply() {
            styleTask?.cancel()
            guard let textView else { return }

            if styleOptions.reduceMotion {
                Task { await parseAndApply(text: textView.text ?? "") }
                return
            }

            styleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                await parseAndApply(text: textView.text ?? "")
            }
        }

        private func parseAndApply(text: String) async {
            let result = await parseActor.parse(text: text)
            cachedConstructs = result.constructs
            applyStyles(constructs: result.constructs)
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
        true
    }
}
#endif
