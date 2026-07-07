//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftTerm
import SwiftUI

/// Hosts the controller-owned SwiftTerm terminal view in SwiftUI.
struct TerminalSessionView: NSViewRepresentable {

    @Environment(AppSettings.self) private var settings

    let controller: TerminalSessionController

    /// Whether this session is the selected tab. The selected terminal grabs
    /// keyboard focus.
    let isSelected: Bool

    func makeNSView(context: Context) -> TerminalView {
        let terminalView = controller.terminalView
        applyFont(to: terminalView)
        return terminalView
    }

    func updateNSView(_ nsView: TerminalView, context: Context) {
        applyFont(to: nsView)
        guard isSelected else { return }
        DispatchQueue.main.async {
            guard let window = nsView.window, window.firstResponder !== nsView else { return }
            window.makeFirstResponder(nsView)
        }
    }

    private func applyFont(to terminalView: TerminalView) {
        let size = CGFloat(settings.terminalFontSize)
        if terminalView.font.pointSize != size {
            terminalView.font = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
    }
}
