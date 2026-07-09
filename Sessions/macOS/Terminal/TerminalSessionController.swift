//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import Foundation
import Observation
import OSLog
import SessionsClient
import SessionsProtocol
import SwiftTerm

/// Owns the terminal view for one session (tab) and its attachment to the
/// session server.
///
/// The controller outlives SwiftUI view updates so that switching tabs or
/// workspaces never tears down the terminal view. The shell process itself
/// lives in the session server; this controller just attaches to it,
/// pumps output bytes into the view, and forwards input/resizes.
@Observable @MainActor
final class TerminalSessionController {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "TerminalSessionController")

    let sessionID: SessionInfo.ID

    let terminalView: SessionsTerminalView

    private let client: SessionServerClient

    private var attachment: SessionAttachment?

    private var pumpTask: Task<Void, Never>?

    /// Title reported by the shell via OSC escape sequences, if any.
    private(set) var shellTitle: String?

    /// Working directory reported by the shell via OSC 7, if any.
    private(set) var currentDirectory: String?

    /// Last cwd forwarded to the server, to avoid resending duplicates
    /// (replay re-emits every historical OSC 7 sequence).
    private var lastReportedCwd: String?

    /// Mirrored from the server's `SessionInfo`.
    private(set) var isAlive = false

    private(set) var exitCode: Int32?

    /// A BEL arrived while this tab was in the background.
    private(set) var hasBell = false

    /// An OSC 9 notification arrived (e.g. a Claude Code hook signaling
    /// that it needs input).
    private(set) var hasNotification = false

    /// Claude Code lifecycle state, driven by `claude:`-prefixed OSC 9
    /// payloads from the bundled hooks. Ordered by badge priority, so a
    /// workspace aggregates its tabs' statuses with `max`.
    enum ClaudeStatus: Int, Comparable {
        case none
        case done
        case working
        case needsInput

        static func < (lhs: Self, rhs: Self) -> Bool {
            lhs.rawValue < rhs.rawValue
        }
    }

    /// Current Claude state in this tab; cleared when the user types.
    private(set) var claudeStatus: ClaudeStatus = .none

    /// Whether this tab wants the user's attention. Claude "working" and
    /// "done" are calm status, not attention — only needs-input (and
    /// legacy signals) light the bell.
    var needsAttention: Bool {
        hasBell || hasNotification || claudeStatus == .needsInput
    }

    /// While the server replays scrollback, the terminal re-parses old
    /// query sequences (e.g. Device Attributes) and generates responses.
    /// Those queries were answered when they originally arrived, so all
    /// terminal→host traffic is dropped until `replayDone` — otherwise
    /// the responses land at the shell prompt as garbage input.
    private var isReplaying = false

    /// Whether the find bar is shown for this tab (state lives here so it
    /// survives tab switches).
    var isFindBarVisible = false

    // MARK: - Find in scrollback

    var findText = "" {
        didSet {
            if findText != oldValue {
                findFailed = false
            }
        }
    }

    var findCaseSensitive = false {
        didSet {
            findFailed = false
        }
    }

    var findRegex = false {
        didSet {
            findFailed = false
        }
    }

    /// The last search found no match (also set for invalid regexes).
    private(set) var findFailed = false

    func showFindBar() {
        isFindBarVisible = true
    }

    func hideFindBar() {
        isFindBarVisible = false
        findFailed = false
        terminalView.clearSearch()
        terminalView.window?.makeFirstResponder(terminalView)
    }

    func findNext() {
        guard !findText.isEmpty else { return }
        let options = SearchOptions(caseSensitive: findCaseSensitive, regex: findRegex)
        findFailed = !terminalView.findNext(findText, options: options, scrollToResult: true)
    }

    func findPrevious() {
        guard !findText.isEmpty else { return }
        let options = SearchOptions(caseSensitive: findCaseSensitive, regex: findRegex)
        findFailed = !terminalView.findPrevious(findText, options: options, scrollToResult: true)
    }

    // MARK: - Appearance

    private var appliedTheme: TerminalTheme?

    private var metalApplyFailedForSetting: Bool?

    /// Applies input behavior settings (cheap; assignment-only).
    func applyInputBehavior(optionAsMetaKey: Bool, confirmMultilinePaste: Bool) {
        terminalView.confirmsMultilinePaste = confirmMultilinePaste
        if terminalView.optionAsMetaKey != optionAsMetaKey {
            terminalView.optionAsMetaKey = optionAsMetaKey
        }
    }

    private var appliedCursorStyle: CursorStyle?

    private var appliedScrollbackLines: Int?

    private var appliedTabStopWidth: Int?

    /// Applies terminal-engine options. Cursor style is a live change;
    /// scrollback and tab stop width require rebuilding the terminal's
    /// buffers (`Terminal.setup`), which clears the screen — the follow-up
    /// re-attach replays the content from the server's ring buffer.
    func applyTerminalOptions(scrollbackLines: Int, tabStopWidth: Int, cursorStyle: CursorStyle) {
        let terminal = terminalView.getTerminal()
        if appliedCursorStyle != cursorStyle {
            appliedCursorStyle = cursorStyle
            terminal.setCursorStyle(cursorStyle)
        }
        let isFirstApplication = appliedScrollbackLines == nil
        let needsRebuild = !isFirstApplication
            && (appliedScrollbackLines != scrollbackLines || appliedTabStopWidth != tabStopWidth)
        appliedScrollbackLines = scrollbackLines
        appliedTabStopWidth = tabStopWidth
        guard isFirstApplication || needsRebuild else { return }
        var options = terminal.options
        options.scrollback = scrollbackLines
        options.tabStopWidth = tabStopWidth
        // Keep the terminal's current size; setup() rebuilds from options.
        options.cols = terminal.cols
        options.rows = terminal.rows
        options.cursorStyle = cursorStyle
        terminal.options = options
        if needsRebuild {
            terminal.setup(isReset: false)
            attach()
        } else {
            // First application happens right after view creation, before
            // any content: rebuild silently, no replay needed beyond the
            // attach that follows anyway.
            terminal.setup(isReset: false)
        }
    }

    /// Applies theme, font, and margin background. Called from every
    /// `updateNSView` pass — including for hidden tabs in the ZStack — so
    /// everything is guarded to be cheap when nothing changed.
    func applyAppearanceIfNeeded(
        theme: TerminalTheme,
        fontName: String,
        fontSize: CGFloat,
        container: TerminalContainerView?
    ) {
        let resolvedFont = Self.resolveFont(name: fontName, size: fontSize)
        if terminalView.font != resolvedFont {
            terminalView.font = resolvedFont
        }
        if appliedTheme != theme {
            appliedTheme = theme
            theme.apply(to: terminalView, container: container)
        } else if let container, container.backgroundColor != terminalView.nativeBackgroundColor {
            container.backgroundColor = terminalView.nativeBackgroundColor
        }
    }

    /// Toggles the experimental Metal renderer. On failure, logs once and
    /// does not retry until the setting changes.
    func applyRendererIfNeeded(useMetal: Bool) {
        guard terminalView.window != nil,
              terminalView.isUsingMetalRenderer != useMetal,
              metalApplyFailedForSetting != useMetal else {
            return
        }
        do {
            try terminalView.setUseMetal(useMetal)
            metalApplyFailedForSetting = nil
        } catch {
            metalApplyFailedForSetting = useMetal
            Self.logger.error("Failed to toggle Metal renderer to \(useMetal): \(error)")
        }
    }

    /// Empty name means the system monospaced font (SF Mono). Otherwise
    /// `name` is a font family; falls back to the system monospaced font
    /// if the family is no longer installed.
    private static func resolveFont(name: String, size: CGFloat) -> NSFont {
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

    init(sessionID: SessionInfo.ID, client: SessionServerClient) {
        self.sessionID = sessionID
        self.client = client
        terminalView = SessionsTerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView.terminalDelegate = self
        // OSC 9 (iTerm2/kitty notification convention): used by tools like
        // Claude Code hooks to signal "needs attention". The handler fires
        // synchronously during feed() on the main actor.
        terminalView.getTerminal().registerOscHandler(code: 9) { [weak self] payload in
            MainActor.assumeIsolated {
                self?.noteNotification(message: String(bytes: payload, encoding: .utf8))
            }
        }
    }

    private func noteNotification(message: String?) {
        // Historical OSC 9 sequences re-fire during scrollback replay;
        // they were handled when they originally arrived.
        guard !isReplaying else { return }
        if let message, message.hasPrefix("claude:") {
            noteClaudeStatus(payload: message)
            return
        }
        // Legacy path: any plain OSC 9 payload is a generic notification.
        hasNotification = true
        postAttentionNotification(body: (message?.isEmpty ?? true) ? "A session needs attention" : message ?? "")
    }

    /// `claude:working` / `claude:input` / `claude:done` from the bundled
    /// hooks. Each payload overwrites the previous state, following
    /// Claude's real lifecycle. Unknown `claude:*` payloads (from newer
    /// hook versions) are treated as needs-input, the safe default.
    private func noteClaudeStatus(payload: String) {
        switch payload {
        case "claude:working":
            claudeStatus = .working
        case "claude:done":
            claudeStatus = .done
            postAttentionNotification(body: "Claude is done")
        default:
            claudeStatus = .needsInput
            postAttentionNotification(body: "Claude needs input")
        }
    }

    private func postAttentionNotification(body: String) {
        let title = shellTitle
            ?? currentDirectory.map { ($0 as NSString).lastPathComponent }
            ?? "Terminal"
        AttentionNotifier.post(title: title, body: body)
    }

    /// Attaches (or re-attaches) to the session. The terminal is reset
    /// before the server replays scrollback, so a re-attach after a crash
    /// or reconnect reconstructs the screen without duplication.
    func attach() {
        pumpTask?.cancel()
        pumpTask = Task {
            // RIS: full terminal reset before the replay arrives.
            terminalView.feed(byteArray: ArraySlice([0x1B, 0x63]))
            let terminal = terminalView.getTerminal()
            let attachment: SessionAttachment?
            attachment = try? await client.attach(
                sessionID: sessionID,
                cols: terminal.cols,
                rows: terminal.rows
            )
            guard let attachment else {
                Self.logger.error("Failed to attach session \(self.sessionID)")
                return
            }
            self.attachment = attachment
            for await event in attachment.events {
                switch event {
                case .replayStarted:
                    isReplaying = true
                case .output(let chunk):
                    terminalView.feed(byteArray: chunk[...])
                case .replayDone:
                    isReplaying = false
                    reportCwdIfChanged()
                }
            }
        }
    }

    func detach() {
        pumpTask?.cancel()
        pumpTask = nil
        attachment = nil
        Task {
            await client.detach(sessionID: sessionID)
        }
    }

    /// Mirrors server state into the controller.
    func applyInfo(_ info: SessionInfo) {
        isAlive = info.isAlive
        exitCode = info.exitCode
    }

    func noteExited(exitCode: Int32?) {
        isAlive = false
        self.exitCode = exitCode ?? -1
    }

    func clearAttention() {
        hasBell = false
        hasNotification = false
        claudeStatus = .none
    }

    /// Never started since the server booted (fresh boot or reboot), as
    /// opposed to exited. Such sessions auto-restart when shown.
    var isDormant: Bool {
        !isAlive && exitCode == nil
    }
}

extension TerminalSessionController: @preconcurrency TerminalViewDelegate {

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        guard !isReplaying else { return }
        // The user is interacting with this tab; attention is served and
        // any Claude status badge (incl. working/done) is stale.
        if needsAttention || claudeStatus != .none {
            clearAttention()
        }
        attachment?.sendInput(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        attachment?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        shellTitle = title.isEmpty ? nil : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        guard let directory, let path = Self.parseOSC7Path(directory) else { return }
        currentDirectory = path
        // During replay, historical OSC 7 sequences fire this repeatedly;
        // record locally and report once on replayDone instead of spamming
        // the socket. Live updates are forwarded immediately.
        if !isReplaying {
            reportCwdIfChanged()
        }
    }

    private func reportCwdIfChanged() {
        guard let path = currentDirectory, path != lastReportedCwd else { return }
        lastReportedCwd = path
        let sessionID = self.sessionID
        let client = self.client
        Task {
            await client.reportCwd(sessionID: sessionID, path: path)
        }
    }

    /// Parses an OSC 7 payload. Shells send `file://host/percent-encoded-path`
    /// by convention, but bare paths occur in the wild.
    static func parseOSC7Path(_ raw: String) -> String? {
        if raw.hasPrefix("/") {
            return raw
        }
        guard let url = URL(string: raw), url.scheme == "file" else { return nil }
        let path = url.path(percentEncoded: false)
        return path.isEmpty ? nil : path
    }

    func scrolled(source: TerminalView, position: Double) {
        // Not used.
    }

    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func bell(source: TerminalView) {
        // Historical BELs still in the scrollback re-fire during replay
        // (badging a tab on every app start); only live bells count.
        guard !isReplaying else { return }
        hasBell = true
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        if let string = String(bytes: content, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }

    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {
        // Not used.
    }

    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {
        // Not used.
    }
}
