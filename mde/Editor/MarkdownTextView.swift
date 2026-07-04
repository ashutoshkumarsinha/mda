//
//  MarkdownTextView.swift
//  MDE
//

#if os(macOS)
import AppKit
import SwiftUI

private final class PlainTextPasteTextView: NSTextView {
    override func paste(_ sender: Any?) {
        guard let string = NSPasteboard.general.string(forType: .string) else {
            super.paste(sender)
            return
        }
        insertText(string, replacementRange: selectedRange())
    }
}

struct MarkdownTextView: NSViewRepresentable {
    @Binding var text: String
    var resolvedLinkTitles: Set<String>
    var baseFontSize: CGFloat
    var reduceMotion: Bool
    var noteTitle: String
    var onTextChange: (String) -> Void
    var onWikiLinkClick: (String) -> Void

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false

        let textStorage = MarkdownTokenTextStorage()
        textStorage.styleOptions = styleOptions
        textStorage.attachStyleController(context.coordinator.styleController)
        if !text.isEmpty {
            textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)
        }

        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer()
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = PlainTextPasteTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = true
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.font = .systemFont(ofSize: baseFontSize)
        textView.textContainerInset = NSSize(width: 16, height: 16)
        textView.backgroundColor = .textBackgroundColor
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        configureAccessibility(on: textView)

        context.coordinator.textView = textView
        context.coordinator.styleController.styleOptions = styleOptions
        context.coordinator.installClickGesture(on: textView)
        context.coordinator.applyStyles(fullDocument: true)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        context.coordinator.resolvedLinkTitles = resolvedLinkTitles
        context.coordinator.styleController.styleOptions = styleOptions
        if let tokenStorage = textView.textStorage as? MarkdownTokenTextStorage {
            tokenStorage.styleOptions = styleOptions
        }
        textView.font = .systemFont(ofSize: baseFontSize)
        configureAccessibility(on: textView)
        if textView.string != text {
            let selected = textView.selectedRanges
            textView.string = text
            textView.selectedRanges = selected
            context.coordinator.applyStyles(fullDocument: true)
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

    private func configureAccessibility(on textView: NSTextView) {
        textView.setAccessibilityLabel(AccessibilityLabels.editorPlaceholder(noteTitle: noteTitle))
        textView.setAccessibilityRole(.textArea)
        textView.setAccessibilityHelp("Markdown note editor")
        textView.setAccessibilityIdentifier("note-editor")
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        @Binding var text: String
        var resolvedLinkTitles: Set<String>
        let styleController = MarkdownEditorStyleController()
        var onTextChange: (String) -> Void
        var onWikiLinkClick: (String) -> Void
        weak var textView: NSTextView?

        init(
            text: Binding<String>,
            resolvedLinkTitles: Set<String>,
            styleOptions: MarkdownStyleOptions,
            onTextChange: @escaping (String) -> Void,
            onWikiLinkClick: @escaping (String) -> Void
        ) {
            _text = text
            self.resolvedLinkTitles = resolvedLinkTitles
            self.onTextChange = onTextChange
            self.onWikiLinkClick = onWikiLinkClick
            super.init()
            styleController.styleOptions = styleOptions
        }

        func textDidChange(_ notification: Notification) {
            guard let textView, !styleController.isStyleApplicationInProgress else { return }
            let updated = textView.string
            text = updated
            onTextChange(updated)
            scheduleStyleApply()
        }

        func textViewDidChangeSelection(_ notification: Notification) {
            scheduleStyleApply()
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard let textView else { return }
            let point = gesture.location(in: textView)
            let index = textView.characterIndexForInsertion(at: point)

            if let toggled = MarkdownEditorLogic.toggleTask(at: index, in: textView.string) {
                let checked = toggled.contains("- [x]") || toggled.contains("- [X]")
                styleController.noteStyleApplicationBegan()
                textView.string = toggled
                text = toggled
                onTextChange(toggled)
                styleController.noteStyleApplicationEnded()
                refreshAfterTextMutation(toggled, caret: index)
                announceTaskToggle(checked: checked, on: textView)
                return
            }

            if let title = MarkdownEditorLogic.wikiLinkTitle(at: index, in: textView.string) {
                onWikiLinkClick(title)
            }
        }

        func applyStyles(
            constructs: [MarkdownConstruct]? = nil,
            styleRange: NSRange? = nil,
            fullDocument: Bool = false
        ) {
            guard let textView, let storage = textView.textStorage else { return }
            if fullDocument, constructs == nil, styleController.cachedConstructs.isEmpty {
                Task {
                    await styleController.parseAndApply(
                        text: textView.string,
                        caretLocation: textView.selectedRange().location,
                        fullDocument: true
                    ) { parsed, _ in
                        self.applyStyles(constructs: parsed, fullDocument: true)
                    }
                }
                return
            }

            styleController.noteStyleApplicationBegan()
            defer { styleController.noteStyleApplicationEnded() }

            let caret = textView.selectedRange().location
            let content = textView.string
            var options = styleController.styleOptions
            options.suspendTokenHide = textView.hasMarkedText()

            let activeConstructs = constructs ?? styleController.cachedConstructs
            let range = fullDocument
                ? nil
                : (styleRange ?? MarkdownLineIndex.stylingNeighborhood(in: content, caretLocation: caret))

            MarkdownStyler.apply(
                to: storage,
                text: content,
                caretLocation: caret,
                constructs: activeConstructs,
                options: options,
                styleRange: range
            )
        }

        private func scheduleStyleApply() {
            guard let textView else { return }
            let caret = textView.selectedRange().location
            let content = textView.string

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

        func installClickGesture(on textView: NSTextView) {
            let gesture = NSClickGestureRecognizer(target: self, action: #selector(handleClick(_:)))
            textView.addGestureRecognizer(gesture)
        }

        private func announceTaskToggle(checked: Bool, on textView: NSTextView) {
            let message = AccessibilityLabels.taskCheckbox(checked: checked)
            textView.setAccessibilityValue(message)
            NSAccessibility.post(
                element: textView,
                notification: .announcementRequested,
                userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.high]
            )
        }
    }
}
#endif
