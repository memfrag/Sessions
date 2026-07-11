//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftTerm

/// SwiftTerm-backed `TerminalEmulator` and the single place that knows
/// SwiftTerm's API.
@MainActor
final class SwiftTermEmulator: NSObject, TerminalEmulator {

    private let terminalView: TerminalView

    weak var delegate: TerminalEmulatorDelegate?

    /// SwiftTerm renders from a headless buffer immediately, so it never
    /// needs the controller to re-attach on surface creation. Unused.
    var onSurfaceReady: (() -> Void)?

    var view: NSView { terminalView }

    var cols: Int { terminalView.getTerminal().cols }

    var rows: Int { terminalView.getTerminal().rows }

    var backgroundColor: NSColor { terminalView.nativeBackgroundColor }

    // Applied-state guards, so the per-`updateNSView` call is cheap when
    // nothing changed.
    private var appliedColors: ColorKey?

    private var appliedCursorStyle: CursorStyle?

    private var appliedScrollbackLines: Int?

    private var appliedTabStopWidth: Int?

    override init() {
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()
        terminalView.terminalDelegate = self
        // Attention sequences (OSC 0/2/7/9, BEL) are parsed by the controller's
        // TerminalStreamScanner from the raw server stream, not here, so they
        // fire for background tabs too.
    }

    // MARK: - TerminalEmulator

    func feed(_ bytes: ArraySlice<UInt8>) {
        terminalView.feed(byteArray: bytes)
    }

    func reset() {
        // RIS.
        terminalView.feed(byteArray: ArraySlice([0x1B, 0x63]))
    }

    func eraseScrollback() {
        // ESC[3J erases the scrollback in the local view.
        terminalView.feed(byteArray: ArraySlice(Array("\u{1B}[3J".utf8)))
    }

    func redraw() {
        terminalView.getTerminal().updateFullScreen()
        terminalView.setNeedsDisplay(terminalView.bounds)
    }

    @discardableResult
    func apply(_ appearance: TerminalAppearance) -> Bool {
        if terminalView.font != appearance.font {
            terminalView.font = appearance.font
        }

        let colorKey = ColorKey(appearance)
        if appliedColors != colorKey {
            appliedColors = colorKey
            applyColors(appearance)
        }

        let cursorStyle = Self.cursorStyle(shape: appearance.cursorShape, blinks: appearance.cursorBlinks)
        if appliedCursorStyle != cursorStyle {
            appliedCursorStyle = cursorStyle
            terminalView.getTerminal().setCursorStyle(cursorStyle)
        }

        let needsReattach = applyBufferOptions(appearance, cursorStyle: cursorStyle)

        if terminalView.optionAsMetaKey != appearance.optionAsMeta {
            terminalView.optionAsMetaKey = appearance.optionAsMeta
        }

        return needsReattach
    }

    // MARK: - Appearance helpers

    /// The system theme starts from macOS-native colors; any non-empty hex
    /// fields (user overrides) then win. Custom themes carry non-empty
    /// fields, so both share one path.
    private func applyColors(_ appearance: TerminalAppearance) {
        if appearance.isSystemTheme {
            terminalView.configureNativeColors()
            terminalView.caretColor = .textColor
            terminalView.caretTextColor = nil
            terminalView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        }
        let hexes = appearance.ansi.isEmpty ? TerminalTheme.xterm16 : appearance.ansi
        let colors = hexes.compactMap { SwiftTerm.Color(hexString: $0) }
        if colors.count == 16 {
            terminalView.installColors(colors)
        }
        if let color = NSColor(hexString: appearance.foreground) {
            terminalView.nativeForegroundColor = color
        }
        if let color = NSColor(hexString: appearance.background) {
            terminalView.nativeBackgroundColor = color
            terminalView.caretTextColor = color
        }
        if let color = NSColor(hexString: appearance.cursor) {
            terminalView.caretColor = color
        }
        if let color = NSColor(hexString: appearance.selection) {
            terminalView.selectedTextBackgroundColor = color
        }
    }

    /// Scrollback and tab-stop width require rebuilding the terminal's
    /// buffers (`setup`), which clears the screen — the caller re-attaches
    /// so the server replays the content. Returns whether a rebuild that
    /// needs a replay happened (not on the first application, whose replay
    /// arrives via the attach that follows anyway).
    private func applyBufferOptions(_ appearance: TerminalAppearance, cursorStyle: CursorStyle) -> Bool {
        let isFirstApplication = appliedScrollbackLines == nil
        let changed = appliedScrollbackLines != appearance.scrollbackLines
            || appliedTabStopWidth != appearance.tabStopWidth
        appliedScrollbackLines = appearance.scrollbackLines
        appliedTabStopWidth = appearance.tabStopWidth
        guard isFirstApplication || changed else { return false }

        let terminal = terminalView.getTerminal()
        var options = terminal.options
        options.scrollback = appearance.scrollbackLines
        options.tabStopWidth = appearance.tabStopWidth
        // Keep the current size; setup() rebuilds from options.
        options.cols = terminal.cols
        options.rows = terminal.rows
        options.cursorStyle = cursorStyle
        terminal.options = options
        terminal.setup(isReset: false)
        return !isFirstApplication && changed
    }

    private static func cursorStyle(shape: TerminalCursorShape, blinks: Bool) -> CursorStyle {
        switch shape {
        case .underline: blinks ? .blinkUnderline : .steadyUnderline
        case .bar: blinks ? .blinkBar : .steadyBar
        case .block: blinks ? .blinkBlock : .steadyBlock
        }
    }

    /// Snapshot of the color-relevant fields, for cheap change detection.
    private struct ColorKey: Equatable {
        let isSystem: Bool
        let ansi: [String]
        let foreground: String
        let background: String
        let cursor: String
        let selection: String

        init(_ appearance: TerminalAppearance) {
            isSystem = appearance.isSystemTheme
            ansi = appearance.ansi
            foreground = appearance.foreground
            background = appearance.background
            cursor = appearance.cursor
            selection = appearance.selection
        }
    }
}

// MARK: - TerminalViewDelegate → TerminalEmulatorDelegate

extension SwiftTermEmulator: @preconcurrency TerminalViewDelegate {

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        delegate?.emulatorSend(data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        delegate?.emulatorResized(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        // Title comes from the controller's stream scanner.
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // cwd comes from the controller's stream scanner.
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        delegate?.emulatorOpenLink(link)
    }

    func bell(source: TerminalView) {
        // Bell comes from the controller's stream scanner.
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        delegate?.emulatorCopy(content)
    }

    func scrolled(source: TerminalView, position: Double) {
        // Not used.
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        // Not used.
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // Not used.
    }
}

// MARK: - SwiftTerm color parsing

extension SwiftTerm.Color {

    /// Parses "#RRGGBB" into SwiftTerm's 16-bit-per-channel color.
    convenience init?(hexString: String) {
        guard let (red, green, blue) = parseHexRGB(hexString) else { return nil }
        self.init(
            red: UInt16(red) * 257,
            green: UInt16(green) * 257,
            blue: UInt16(blue) * 257
        )
    }
}
