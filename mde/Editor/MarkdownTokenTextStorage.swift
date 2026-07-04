//
//  MarkdownTokenTextStorage.swift
//  MDE
//
//  Foundation for HLD hybrid-token rendering: NSTextStorage subclass that
//  coordinates Markdown styling passes without replacing the full document.
//

#if os(macOS)
import AppKit

final class MarkdownTokenTextStorage: NSTextStorage {
    private let backingStore = NSMutableAttributedString()
    private weak var sharedStyleController: MarkdownEditorStyleController?

    var styleOptions = MarkdownStyleOptions() {
        didSet { sharedStyleController?.styleOptions = styleOptions }
    }

    var onTextChange: ((String) -> Void)?

    func attachStyleController(_ controller: MarkdownEditorStyleController) {
        sharedStyleController = controller
        controller.styleOptions = styleOptions
    }

    override var string: String {
        backingStore.string
    }

    override func attributes(at location: Int, effectiveRange range: NSRangePointer?) -> [NSAttributedString.Key: Any] {
        backingStore.attributes(at: location, effectiveRange: range)
    }

    override func replaceCharacters(in range: NSRange, with str: String) {
        beginEditing()
        backingStore.replaceCharacters(in: range, with: str)
        edited(.editedCharacters, range: range, changeInLength: (str as NSString).length - range.length)
        endEditing()
        onTextChange?(string)
    }

    override func setAttributes(_ attrs: [NSAttributedString.Key: Any]?, range: NSRange) {
        beginEditing()
        backingStore.setAttributes(attrs, range: range)
        edited(.editedAttributes, range: range, changeInLength: 0)
        endEditing()
    }

    func applyStyles(caretLocation: Int, constructs: [MarkdownConstruct], styleRange: NSRange? = nil) {
        MarkdownStyler.apply(
            to: backingStore,
            text: string,
            caretLocation: caretLocation,
            constructs: constructs,
            options: styleOptions,
            styleRange: styleRange
        )
    }

    func scheduleStylePass(caretLocation: Int) {
        guard let sharedStyleController else { return }
        sharedStyleController.scheduleStyleApply(text: string, caretLocation: caretLocation) { [weak self] constructs, range in
            guard let self else { return }
            self.applyStyles(caretLocation: caretLocation, constructs: constructs, styleRange: range)
        }
    }
}
#endif
