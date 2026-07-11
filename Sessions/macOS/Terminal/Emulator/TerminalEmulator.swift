//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// Engine-neutral interface for the terminal emulator + rendered view that
/// `TerminalSessionController` drives. `GhosttyEmulator` (libghostty) is the
/// backend; this seam confines the dependency so an alternative engine can
/// be a drop-in.
///
/// The emulator is headless with respect to the process: the PTY lives in
/// the session server. Server output is pushed in via `feed`, and user
/// input / query responses come back out through `TerminalEmulatorDelegate`.
@MainActor
protocol TerminalEmulator: AnyObject {

    /// The AppKit view that renders the terminal (hosted by the app).
    var view: NSView { get }

    var delegate: TerminalEmulatorDelegate? { get set }

    /// Invoked when the render surface first becomes available (or is
    /// re-created). The controller re-attaches in response so the server
    /// replays scrollback into the now-live surface. An engine with a headless
    /// buffer that renders from the start need not call this.
    var onSurfaceReady: (() -> Void)? { get set }

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

    /// Applies appearance/behavior settings. Returns `true` when the change
    /// rebuilt the terminal buffers and the caller should re-attach so the
    /// server replays the content back.
    @discardableResult
    func apply(_ appearance: TerminalAppearance) -> Bool
}

/// Callbacks from the emulator toward the controller.
///
/// Attention signals (title, bell, cwd, OSC 9) are intentionally *not* here:
/// the controller parses those from the raw server stream with
/// `TerminalStreamScanner` so they work for background/never-mounted tabs
/// regardless of whether a render surface exists. This delegate only carries
/// callbacks tied to a live, on-screen surface.
@MainActor
protocol TerminalEmulatorDelegate: AnyObject {

    /// User keystrokes and terminal query responses to relay to the server.
    func emulatorSend(_ bytes: ArraySlice<UInt8>)

    func emulatorResized(cols: Int, rows: Int)

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
