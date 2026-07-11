//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import GhosttyTerminal
import OSLog

/// libghostty-backed `TerminalEmulator`. Wraps an `AppTerminalView` +
/// `InMemoryTerminalSession` and is the single place that knows the
/// libghostty-spm API.
///
/// Unlike SwiftTerm, Ghostty's terminal buffer lives in a render *surface*
/// that only exists once the view is in a window and sized. Bytes fed before
/// the surface exists are dropped, so the controller re-attaches (replaying
/// the server's ring) when `onSurfaceReady` fires. The surface then persists
/// across mount/unmount, so no further re-attach is needed while the emulator
/// lives.
@MainActor
final class GhosttyEmulator: NSObject, TerminalEmulator {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "GhosttyEmulator")

    /// One ghostty app + config drives every surface. Sessions applies a
    /// single global appearance to all terminals, so a shared controller is
    /// both correct and cheap: config changes push live to all surfaces
    /// (`ghostty_surface_update_config`) without rebuilding them.
    @MainActor
    private enum Shared {
        // Empty theme: Sessions puts every color in `terminalConfiguration`,
        // so a non-empty theme (e.g. `.default`) would render its own color
        // block *after* ours and override it — and its bare-hex values can
        // fail validation, which rejects the whole config.
        static let controller = TerminalController(
            configSource: .none,
            theme: GhosttyTerminal.TerminalTheme(),
            terminalConfiguration: .default
        )
    }

    /// Rough bytes-per-line factor to translate Sessions' line-based
    /// scrollback setting into Ghostty's byte-based `scrollback-limit`.
    private static let bytesPerScrollbackLine = 256

    /// Internal cell margin (replaces the old outer container inset).
    private static let windowPaddingX = 8
    private static let windowPaddingY = 8

    private let terminalView: AppTerminalView

    private let session: InMemoryTerminalSession

    weak var delegate: TerminalEmulatorDelegate?

    var onSurfaceReady: (() -> Void)?

    var view: NSView { terminalView }

    private var trackedCols = 80

    private var trackedRows = 24

    var cols: Int { trackedCols }

    var rows: Int { trackedRows }

    private(set) var backgroundColor: NSColor = .textBackgroundColor

    /// Last config pushed to the shared controller, to skip redundant work.
    private var appliedConfiguration: TerminalConfiguration?

    override init() {
        let box = SessionBox()
        session = InMemoryTerminalSession(
            write: { data in
                // May fire on the main thread (keystrokes via ghostty_surface_key)
                // or on the session's background output queue (query responses
                // generated while parsing fed bytes), so hop to the main actor
                // rather than assuming isolation.
                Task { @MainActor in
                    box.emulator?.delegate?.emulatorSend(Array(data)[...])
                }
            },
            resize: { viewport in
                Task { @MainActor in
                    box.emulator?.handleResize(viewport)
                }
            }
        )
        terminalView = AppTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        super.init()
        box.emulator = self
        terminalView.delegate = self
        terminalView.controller = Shared.controller
        terminalView.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
    }

    /// Breaks the retain cycle between the `@Sendable` session callbacks and
    /// the emulator: the callbacks capture this box (not the emulator), and
    /// the box holds the emulator weakly.
    private final class SessionBox: @unchecked Sendable {
        weak var emulator: GhosttyEmulator?
    }

    private func handleResize(_ viewport: InMemoryTerminalViewport) {
        trackedCols = Int(viewport.columns)
        trackedRows = Int(viewport.rows)
        delegate?.emulatorResized(cols: trackedCols, rows: trackedRows)
    }

    // MARK: - TerminalEmulator

    func feed(_ bytes: ArraySlice<UInt8>) {
        session.receive(Data(bytes))
    }

    func reset() {
        // RIS.
        session.receive(Data([0x1B, 0x63]))
    }

    func eraseScrollback() {
        // ESC[3J erases the scrollback in the local buffer.
        session.receive(Data("\u{1B}[3J".utf8))
    }

    func redraw() {
        // The surface self-drives its render loop; nudge it to repaint after
        // becoming visible.
        terminalView.fitToSize()
    }

    func focus() {
        terminalView.window?.makeFirstResponder(terminalView)
    }

    @discardableResult
    func apply(_ appearance: TerminalAppearance) -> Bool {
        backgroundColor = effectiveBackgroundColor(appearance)

        let configuration = buildConfiguration(appearance)
        if appliedConfiguration != configuration {
            appliedConfiguration = configuration
            if !Shared.controller.setTerminalConfiguration(configuration),
               let issue = Shared.controller.lastConfigurationIssue {
                Self.logger.error("Ghostty rejected terminal configuration: \(issue)")
            }
        }
        // Ghostty applies every change live (no buffer rebuild), so the
        // controller never needs to re-attach on an appearance change.
        return false
    }

    // Search has no libghostty-spm API (`readViewportText` is viewport-only),
    // so find-in-scrollback is unavailable with this backend.
    @discardableResult
    func find(_ text: String, forward: Bool, caseSensitive: Bool, regex: Bool) -> Bool {
        false
    }

    func clearSearch() {}

    // MARK: - Appearance mapping

    private func buildConfiguration(_ appearance: TerminalAppearance) -> TerminalConfiguration {
        var configuration = TerminalConfiguration()

        configuration = configuration.fontSize(Float(appearance.font.pointSize))
        if let family = fontFamily(appearance.font) {
            configuration = configuration.fontFamily(family)
        }

        configuration = configuration
            .cursorStyle(cursorStyle(appearance.cursorShape))
            .cursorStyleBlink(appearance.cursorBlinks)

        let ansi = appearance.ansi.isEmpty ? TerminalTheme.xterm16 : appearance.ansi
        for (index, hex) in ansi.enumerated() where !hex.isEmpty {
            configuration = configuration.palette(index, color: hex)
        }

        configuration = configuration
            .foreground(appearance.foreground.isEmpty ? hex(.textColor) : appearance.foreground)
            .background(appearance.background.isEmpty ? hex(.textBackgroundColor) : appearance.background)
        if !appearance.cursor.isEmpty {
            configuration = configuration.cursorColor(appearance.cursor)
        }
        if !appearance.selection.isEmpty {
            configuration = configuration.selectionBackground(appearance.selection)
        }

        if appearance.scrollbackLines > 0 {
            let bytes = appearance.scrollbackLines * Self.bytesPerScrollbackLine
            configuration = configuration.custom("scrollback-limit", String(bytes))
        }
        configuration = configuration.custom(
            "macos-option-as-alt",
            appearance.optionAsMeta ? "true" : "false"
        )

        configuration = configuration
            .windowPaddingX(Self.windowPaddingX)
            .windowPaddingY(Self.windowPaddingY)

        // Clear libghostty's default keybinds so app-level shortcuts (⌘⇧P
        // command palette, ⌘T new tab, ⌘W close, ⌘1–9, etc.) fall through to
        // Sessions' menus instead of being consumed by the focused terminal.
        // Re-add only the terminal clipboard actions Sessions wants the
        // engine to handle.
        configuration = configuration
            .custom("keybind", "clear")
            .custom("keybind", "super+c=copy_to_clipboard")
            .custom("keybind", "super+v=paste_from_clipboard")
            .custom("keybind", "super+a=select_all")

        return configuration
    }

    private func effectiveBackgroundColor(_ appearance: TerminalAppearance) -> NSColor {
        NSColor(hexString: appearance.background) ?? resolvedColor(.textBackgroundColor)
    }

    private func fontFamily(_ font: NSFont) -> String? {
        // A dot-prefixed family name is a private system font (e.g. the
        // monospaced system font) that ghostty can't resolve; fall back to
        // its bundled default in that case.
        guard let family = font.familyName, !family.hasPrefix(".") else { return nil }
        return family
    }

    private func cursorStyle(_ shape: TerminalCursorShape) -> TerminalCursorStyle {
        switch shape {
        case .block: .block
        case .underline: .underline
        case .bar: .bar
        }
    }

    /// Resolves a (possibly dynamic) color against the view's current
    /// appearance and formats it as `#RRGGBB` for a ghostty config line.
    private func hex(_ color: NSColor) -> String {
        let resolved = resolvedColor(color)
        return String(
            format: "#%02X%02X%02X",
            Int((resolved.redComponent * 255).rounded()),
            Int((resolved.greenComponent * 255).rounded()),
            Int((resolved.blueComponent * 255).rounded())
        )
    }

    private func resolvedColor(_ color: NSColor) -> NSColor {
        var resolved = color
        terminalView.effectiveAppearance.performAsCurrentDrawingAppearance {
            resolved = color.usingColorSpace(.sRGB) ?? color
        }
        return resolved
    }
}

// MARK: - Surface delegate

extension GhosttyEmulator: TerminalSurfaceLifecycleDelegate, TerminalSurfaceOpenURLDelegate {

    func terminalDidAttachSurface(_ surface: TerminalSurface) {
        // The render surface now exists; ask the controller to replay the
        // server ring into it. Bytes fed before this point were dropped.
        onSurfaceReady?()
    }

    func terminalDidDetachSurface() {
        // The surface persists across mount/unmount, so a detach only happens
        // on real teardown; nothing to do.
    }

    func terminalDidRequestOpenURL(_ url: String, kind: TerminalOpenURLKind) {
        delegate?.emulatorOpenLink(url)
    }
}
