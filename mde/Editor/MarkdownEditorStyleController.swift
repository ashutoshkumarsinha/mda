//
//  MarkdownEditorStyleController.swift
//  MDE
//

import Foundation

@MainActor
final class MarkdownEditorStyleController {
    var styleOptions = MarkdownStyleOptions()

    private let parseActor = MarkdownParseActor()
    private var styleTask: Task<Void, Never>?
    private(set) var isApplyingStyles = false
    private(set) var cachedConstructs: [MarkdownConstruct] = []

    private let parseDebounceMS: UInt64 = 300

    func scheduleStyleApply(
        text: String,
        caretLocation: Int,
        fullDocument: Bool = false,
        apply: @escaping (_ constructs: [MarkdownConstruct], _ styleRange: NSRange?) -> Void
    ) {
        styleTask?.cancel()

        if styleOptions.reduceMotion {
            Task { await parseAndApply(text: text, caretLocation: caretLocation, fullDocument: fullDocument, apply: apply) }
            return
        }

        styleTask = Task {
            try? await Task.sleep(for: .milliseconds(parseDebounceMS))
            guard !Task.isCancelled else { return }
            await parseAndApply(text: text, caretLocation: caretLocation, fullDocument: fullDocument, apply: apply)
        }
    }

    func applyStylesImmediately(
        text: String,
        caretLocation: Int,
        constructs: [MarkdownConstruct],
        fullDocument: Bool = false,
        apply: (_ constructs: [MarkdownConstruct], _ styleRange: NSRange?) -> Void
    ) {
        styleTask?.cancel()
        cachedConstructs = constructs
        let styleRange = fullDocument ? nil : MarkdownLineIndex.stylingNeighborhood(in: text, caretLocation: caretLocation)
        apply(constructs, styleRange)
    }

    func parseAndApply(
        text: String,
        caretLocation: Int,
        fullDocument: Bool = false,
        apply: @escaping (_ constructs: [MarkdownConstruct], _ styleRange: NSRange?) -> Void
    ) async {
        let result = await parseActor.parse(text: text, caretLocation: caretLocation)
        cachedConstructs = result.constructs
        let styleRange = fullDocument ? nil : result.styleRange
        apply(result.constructs, styleRange)
    }

    func noteStyleApplicationBegan() {
        isApplyingStyles = true
    }

    func noteStyleApplicationEnded() {
        isApplyingStyles = false
    }

    var isStyleApplicationInProgress: Bool { isApplyingStyles }
}
