//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

/// A monospaced multi-line text editor that highlights `{{placeholder}}`
/// tokens as the user types. Wraps `NSTextView` because SwiftUI's
/// `TextEditor` cannot style ranges of its content.
struct PlaceholderHighlightingEditor: NSViewRepresentable {

    @Binding var text: String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = PlainTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.font = Self.font
        textView.textContainerInset = NSSize(width: 6, height: 8)
        textView.drawsBackground = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(
            width: 0,
            height: CGFloat.greatestFiniteMagnitude
        )
        textView.string = text
        context.coordinator.highlight(textView)

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.borderType = .noBorder
        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        // Refresh the coordinator's binding: SwiftUI reuses the same view
        // and coordinator across selection changes, so without this a
        // stale binding would write edits back to the previously selected
        // snippet.
        context.coordinator.parent = self
        guard let textView = scrollView.documentView as? NSTextView else { return }
        // Only when the model changed underneath us (e.g. a different
        // snippet was selected) — never while the user is typing.
        if textView.string != text {
            textView.string = text
            context.coordinator.highlight(textView)
        }
    }

    static let font = NSFont.monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)

    final class Coordinator: NSObject, NSTextViewDelegate {

        var parent: PlaceholderHighlightingEditor

        init(_ parent: PlaceholderHighlightingEditor) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            highlight(textView)
        }

        /// Repaints the whole buffer: default text color plus an accent
        /// tint and subtle background on each placeholder token.
        func highlight(_ textView: NSTextView) {
            guard let storage = textView.textStorage else { return }
            let fullRange = NSRange(location: 0, length: storage.length)
            storage.beginEditing()
            storage.setAttributes(
                [.font: PlaceholderHighlightingEditor.font, .foregroundColor: NSColor.labelColor],
                range: fullRange
            )
            for range in Snippet.placeholderRanges(in: textView.string) {
                storage.addAttribute(.foregroundColor, value: NSColor.controlAccentColor, range: range)
                storage.addAttribute(
                    .backgroundColor,
                    value: NSColor.controlAccentColor.withAlphaComponent(0.12),
                    range: range
                )
            }
            storage.endEditing()
        }
    }
}

/// `NSTextView` with all automatic substitutions hard-disabled. Setting
/// the `isAutomatic…` properties in code does not stick — macOS re-enables
/// them from the global preference when the view joins the responder
/// chain — so the getters are overridden to always report off. Snippets
/// are code/commands, where smart quotes and dashes corrupt the text.
private final class PlainTextView: NSTextView {

    override var isAutomaticQuoteSubstitutionEnabled: Bool {
        get { false }
        set {}
    }

    override var isAutomaticDashSubstitutionEnabled: Bool {
        get { false }
        set {}
    }

    override var isAutomaticTextReplacementEnabled: Bool {
        get { false }
        set {}
    }

    override var isAutomaticSpellingCorrectionEnabled: Bool {
        get { false }
        set {}
    }
}
