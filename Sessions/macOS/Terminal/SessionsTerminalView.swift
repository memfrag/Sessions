//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftTerm

/// SwiftTerm terminal view with paste safety: pasting text that contains
/// newlines is confirmed first, since the shell may execute each line
/// immediately. `paste(_:)` is the single paste path on macOS (⌘V arrives
/// via the responder chain), so overriding it covers everything.
final class SessionsTerminalView: TerminalView {

    /// Toggled from settings via the session controller.
    var confirmsMultilinePaste = true

    override func paste(_ sender: Any) {
        guard confirmsMultilinePaste,
              let text = NSPasteboard.general.string(forType: .string),
              text.contains(where: { $0 == "\n" || $0 == "\r" }) else {
            super.paste(sender)
            return
        }
        let lineCount = text.split(omittingEmptySubsequences: false) { $0 == "\n" || $0 == "\r" }.count
        let alert = NSAlert()
        alert.messageText = "Paste \(lineCount) lines?"
        alert.informativeText = "The text contains newlines, so the shell may execute it immediately.\n\n"
            + Self.preview(of: text)
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Paste")
        alert.addButton(withTitle: "Cancel")
        if let window {
            alert.beginSheetModal(for: window) { [weak self] response in
                guard response == .alertFirstButtonReturn else { return }
                self?.performPaste(sender)
            }
        } else if alert.runModal() == .alertFirstButtonReturn {
            performPaste(sender)
        }
    }

    private func performPaste(_ sender: Any) {
        super.paste(sender)
    }

    /// First line of the pasted text, truncated, as a reminder of what is
    /// on the clipboard.
    private static func preview(of text: String) -> String {
        let firstLine = text.split(omittingEmptySubsequences: true) { $0 == "\n" || $0 == "\r" }
            .first.map(String.init) ?? ""
        let trimmed = firstLine.trimmingCharacters(in: .whitespaces)
        let truncated = trimmed.count > 60 ? String(trimmed.prefix(60)) + "…" : trimmed
        return truncated.isEmpty ? "" : "Begins with: \(truncated)"
    }
}
