//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

/// Hosts the controller-owned terminal view in SwiftUI, inset by a small
/// margin inside a background-matching container.
struct TerminalSessionView: NSViewRepresentable {

    @Environment(AppSettings.self) private var settings

    @Environment(WorkspacesModel.self) private var model

    let controller: TerminalSessionController

    /// Whether this session is the selected tab. The selected terminal grabs
    /// keyboard focus.
    let isSelected: Bool

    func makeNSView(context: Context) -> TerminalContainerView {
        let container = TerminalContainerView()
        let terminalView = controller.emulator.view
        container.addSubview(terminalView)
        container.hostedView = terminalView
        applyAppearance(container: container)
        return container
    }

    func updateNSView(_ nsView: TerminalContainerView, context: Context) {
        // The controller keeps one terminal view for the session's lifetime;
        // if SwiftUI hands this representable a recycled container, re-home it.
        let terminalView = controller.emulator.view
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
                  // Only claim focus in the key window. Grabbing focus in a
                  // background window makes the terminal fire a focus-in
                  // event (mode 1004) that reaches the shell — which a TUI
                  // prompt (e.g. Claude Code's question) can read as a key.
                  window.isKeyWindow,
                  window.firstResponder !== terminalView else { return }
            window.makeFirstResponder(terminalView)
        }
    }

    private func applyAppearance(container: TerminalContainerView) {
        let theme = TerminalTheme.theme(withID: settings.terminalThemeID, custom: settings.customTerminalThemes)
            .applying(settings.terminalThemeOverrides[settings.terminalThemeID])
        let appearance = TerminalAppearance(
            isSystemTheme: theme.isSystem,
            ansi: theme.ansi,
            foreground: theme.foreground,
            background: theme.background,
            cursor: theme.cursor,
            selection: theme.selection,
            font: TerminalAppearance.font(
                name: settings.terminalFontName,
                size: CGFloat(settings.terminalFontSize)
            ),
            cursorShape: TerminalCursorShape(rawValue: settings.terminalCursorShape) ?? .block,
            cursorBlinks: settings.terminalCursorBlinks,
            scrollbackLines: settings.terminalScrollbackLines,
            tabStopWidth: settings.terminalTabStopWidth,
            optionAsMeta: settings.optionAsMetaKey,
            confirmMultilinePaste: settings.confirmMultilinePaste,
            useMetal: settings.useMetalRenderer
        )
        controller.applyAppearance(appearance)
        // Keep the margin container's background matching the terminal.
        if container.backgroundColor != controller.emulator.backgroundColor {
            container.backgroundColor = controller.emulator.backgroundColor
        }
    }
}
