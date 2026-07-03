//
//  MarkdownTextView.swift
//  MDE
//

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var resolvedLinkTitles: Set<String>
    var onTextChange: (String) -> Void
    var onWikiLinkClick: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? NSTextView else {
            return scrollView
        }

        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: 15)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.string = text
        textView.backgroundColor = .textBackgroundColor

        context.coordinator.textView = textView
        context.coordinator.installClickGesture(on: textView)
        context.coordinator.applyStyles()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.resolvedLinkTitles = resolvedLinkTitles
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.applyStyles()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            text: $text,
            resolvedLinkTitles: resolvedLinkTitles,
            onTextChange: onTextChange,
            onWikiLinkClick: onWikiLinkClick
        )
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var resolvedLinkTitles: Set<String>
        var onTextChange: (String) -> Void
        var onWikiLinkClick: (String) -> Void
        weak var textView: NSTextView?
        private var styleTask: Task<Void, Never>?
        private var isApplyingStyles = false

        init(
            text: Binding<String>,
            resolvedLinkTitles: Set<String>,
            onTextChange: @escaping (String) -> Void,
            onWikiLinkClick: @escaping (String) -> Void
        ) {
            _text = text
            self.resolvedLinkTitles = resolvedLinkTitles
            self.onTextChange = onTextChange
            self.onWikiLinkClick = onWikiLinkClick
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !isApplyingStyles else { return }
            let updated = textView.string
            text = updated
            onTextChange(updated)
            scheduleStyleApply()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleStyleApply()
        }

        func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
            false
        }

        func textView(_ textView: NSTextView, shouldChangeTextIn affectedCharRange: NSRange, replacementString: String?) -> Bool {
            true
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            let index = textView.characterIndexForInsertion(at: point)

            if let toggled = TaskListHelper.toggleTask(at: index, in: textView.string) {
                isApplyingStyles = true
                textView.string = toggled
                text = toggled
                onTextChange(toggled)
                isApplyingStyles = false
                applyStyles()
                return
            }

            for link in WikiLinkExtractor.linkRanges(in: textView.string) {
                if NSLocationInRange(index, link.titleRange) || NSLocationInRange(index, link.fullRange) {
                    onWikiLinkClick(link.title)
                    return
                }
            }
        }

        func applyStyles() {
            guard let textView, let storage = textView.textStorage else { return }
            isApplyingStyles = true
            let caret = textView.selectedRange().location
            MarkdownStyler.apply(to: storage, text: textView.string, caretLocation: caret)
            isApplyingStyles = false
        }

        private func scheduleStyleApply() {
            styleTask?.cancel()
            styleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                applyStyles()
            }
        }

        func installClickGesture(on textView: NSTextView) {
            let gesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            textView.addGestureRecognizer(gesture)
        }
    }
}
