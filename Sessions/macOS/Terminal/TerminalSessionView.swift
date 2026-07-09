//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftTerm
import SwiftUI

/// Hosts the controller-owned SwiftTerm terminal view in SwiftUI, inset by
/// a small margin inside a background-matching container.
struct TerminalSessionView: NSViewRepresentable {

    @Environment(AppSettings.self) private var settings

    @Environment(WorkspacesModel.self) private var model

    let controller: TerminalSessionController

    /// Whether this session is the selected tab. The selected terminal grabs
    /// keyboard focus.
    let isSelected: Bool

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        let terminalView = controller.terminalView
        container.addSubview(terminalView)
        container.hostedView = terminalView
        applyAppearance(container: container)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        // The controller keeps one terminal view for the session's lifetime;
        // if SwiftUI hands this representable a recycled container, re-home it.
        let terminalView = controller.terminalView
        if terminalView.superview !== nsView {
            terminalView.removeFromSuperview()
            nsView.addSubview(terminalView)
            nsView.hostedView = terminalView
        }
        applyAppearance(container: nsView)
        guard isSelected, !controller.isFindBarVisible, !model.isCommandPaletteVisible else { return }
        // The conditions are re-checked when the block fires: a grab
        // scheduled just before the find bar or command palette opened
        // must not steal focus back from their text fields.
        let model = self.model
        let controller = self.controller
        DispatchQueue.main.async {
            guard !controller.isFindBarVisible,
                  !model.isCommandPaletteVisible,
                  let window = terminalView.window,
                  window.firstResponder !== terminalView else { return }
            window.makeFirstResponder(terminalView)
        }
    }

    private func applyAppearance(container: TerminalContainerView) {
        let theme = TerminalTheme.theme(withID: settings.terminalThemeID)
            .applying(settings.terminalThemeOverrides[settings.terminalThemeID])
        controller.applyAppearanceIfNeeded(
            theme: theme,
            fontName: settings.terminalFontName,
            fontSize: CGFloat(settings.terminalFontSize),
            container: container
        )
        controller.applyRendererIfNeeded(useMetal: settings.useMetalRenderer)
        controller.applyInputBehavior(
            optionAsMetaKey: settings.optionAsMetaKey,
            confirmMultilinePaste: settings.confirmMultilinePaste
        )
        controller.applyTerminalOptions(
            scrollbackLines: settings.terminalScrollbackLines,
            tabStopWidth: settings.terminalTabStopWidth,
            cursorStyle: Self.cursorStyle(
                shape: settings.terminalCursorShape,
                blinks: settings.terminalCursorBlinks
            )
        )
    }

    private static func cursorStyle(shape: String, blinks: Bool) -> CursorStyle {
        switch shape {
        case "underline": blinks ? .blinkUnderline : .steadyUnderline
        case "bar": blinks ? .blinkBar : .steadyBar
        default: blinks ? .blinkBlock : .steadyBlock
        }
    }
}
