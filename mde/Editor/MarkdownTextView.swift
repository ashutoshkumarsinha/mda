//
//  MarkdownTextView.swift
//  MDE
//

import AppKit
import SwiftUI

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var onTextChange: (String) -> Void

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
        context.coordinator.applyStyles()

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.applyStyles()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text, onTextChange: onTextChange)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var onTextChange: (String) -> Void
        weak var textView: NSTextView?
        private var styleTask: Task<Void, Never>?

        init(text: Binding<String>, onTextChange: @escaping (String) -> Void) {
            _text = text
            self.onTextChange = onTextChange
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            let updated = textView.string
            text = updated
            onTextChange(updated)
            scheduleStyleApply()
        }

        func applyStyles() {
            guard let textView, let storage = textView.textStorage else { return }
            MarkdownStyler.apply(to: storage, text: textView.string)
        }

        private func scheduleStyleApply() {
            styleTask?.cancel()
            styleTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                guard !Task.isCancelled else { return }
                applyStyles()
            }
        }
    }
}
