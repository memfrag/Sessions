//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// Engine-neutral interface for the terminal emulator + rendered view that
/// `TerminalSessionController` drives. SwiftTerm is the current backend
/// (`SwiftTermEmulator`); this seam confines the dependency so an
/// alternative engine (e.g. libghostty) can be a drop-in.
///
/// The emulator is headless with respect to the process: the PTY lives in
/// the session server. Server output is pushed in via `feed`, and user
/// input / query responses come back out through `TerminalEmulatorDelegate`.
@MainActor
protocol TerminalEmulator: AnyObject {

    /// The AppKit view that renders the terminal (hosted by the app).
    var view: NSView { get }

    var delegate: TerminalEmulatorDelegate? { get set }

    var cols: Int { get }

    var rows: Int { get }

    /// Effective background color, so the host container can match it.
    var backgroundColor: NSColor { get }

    /// Feeds server output bytes into the emulator.
    func feed(_ bytes: ArraySlice<UInt8>)

    /// Full reset (RIS) — used before a scrollback replay.
    func reset()

    /// Erases the scrollback history, keeping the visible screen.
    func eraseScrollback()

    /// Forces a full repaint from the buffer (e.g. after being re-shown).
    func redraw()

    /// Makes the view first responder (used when closing the find bar).
    func focus()

    /// Applies appearance/behavior settings. Returns `true` when the change
    /// rebuilt the terminal buffers and the caller should re-attach so the
    /// server replays the content back.
    @discardableResult
    func apply(_ appearance: TerminalAppearance) -> Bool

    @discardableResult
    func find(_ text: String, forward: Bool, caseSensitive: Bool, regex: Bool) -> Bool

    func clearSearch()
}

/// Callbacks from the emulator toward the controller.
@MainActor
protocol TerminalEmulatorDelegate: AnyObject {

    /// User keystrokes and terminal query responses to relay to the server.
    func emulatorSend(_ bytes: ArraySlice<UInt8>)

    func emulatorResized(cols: Int, rows: Int)

    /// Title from OSC 0/2 (empty string means "no title").
    func emulatorTitle(_ title: String)

    func emulatorBell()

    /// Raw OSC 7 working-directory payload.
    func emulatorCwd(_ directory: String?)

    /// Raw OSC 9 notification payload (e.g. Claude Code hooks).
    func emulatorNotification(_ payload: String?)

    /// OSC 52 clipboard copy.
    func emulatorCopy(_ content: Data)

    func emulatorOpenLink(_ link: String)
}

/// Cursor shapes, decoupled from any engine's enum.
enum TerminalCursorShape: String {
    case block
    case underline
    case bar
}

/// Engine-neutral appearance + behavior snapshot. Colors are "#RRGGBB" hex
/// strings; an empty string means "use the native/default color".
struct TerminalAppearance {

    /// The system theme starts from macOS-native colors.
    var isSystemTheme: Bool

    /// 16 ANSI colors (0–7 normal, 8–15 bright); empty ⇒ standard xterm 16.
    var ansi: [String]

    var foreground: String

    var background: String

    var cursor: String

    var selection: String

    var font: NSFont

    var cursorShape: TerminalCursorShape

    var cursorBlinks: Bool

    var scrollbackLines: Int

    var tabStopWidth: Int

    var optionAsMeta: Bool

    var confirmMultilinePaste: Bool

    var useMetal: Bool

    /// Empty name means the system monospaced font (SF Mono). Otherwise a
    /// font family; falls back to the system monospaced font if missing.
    static func font(name: String, size: CGFloat) -> NSFont {
        if !name.isEmpty {
            if let font = NSFontManager.shared.font(withFamily: name, traits: [], weight: 5, size: size) {
                return font
            }
            if let font = NSFont(name: name, size: size) {
                return font
            }
        }
        return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }
}
