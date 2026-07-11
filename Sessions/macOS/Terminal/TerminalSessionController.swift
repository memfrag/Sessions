//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import Foundation
import Observation
import OSLog
import SessionsClient
import SessionsProtocol

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

    /// The terminal engine + rendered view (SwiftTerm today, behind the
    /// `TerminalEmulator` seam).
    let emulator: TerminalEmulator

    private let client: SessionServerClient

    /// Parses attention sequences (title, cwd, bell, OSC 9) out of the raw
    /// server stream, independent of the render engine — so background and
    /// never-mounted tabs still drive badges even when the Ghostty backend
    /// has no surface to parse into.
    private let scanner = TerminalStreamScanner()

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
        emulator.clearSearch()
        emulator.focus()
    }

    func findNext() {
        guard !findText.isEmpty else { return }
        findFailed = !emulator.find(findText, forward: true, caseSensitive: findCaseSensitive, regex: findRegex)
    }

    func findPrevious() {
        guard !findText.isEmpty else { return }
        findFailed = !emulator.find(findText, forward: false, caseSensitive: findCaseSensitive, regex: findRegex)
    }

    // MARK: - Appearance

    /// Applies appearance/behavior settings to the emulator. Called from
    /// every `updateNSView` pass — including for hidden tabs — so the
    /// emulator guards each sub-change to stay cheap when nothing changed.
    /// A scrollback/tab-stop change rebuilds the buffers and requires a
    /// re-attach so the server replays the content back.
    func applyAppearance(_ appearance: TerminalAppearance) {
        if emulator.apply(appearance) {
            attach()
        }
    }

    /// Clears the scrollback (like a terminal "clear buffer") and redraws
    /// the prompt. Clears the local view's scrollback, tells the server to
    /// drop its ring (so a re-attach won't replay it), then sends Ctrl-L so
    /// the shell repaints its prompt on a clean screen.
    func clearScrollback() {
        guard !isReplaying else { return }
        emulator.eraseScrollback()
        let sessionID = self.sessionID
        let client = self.client
        let attachment = self.attachment
        Task {
            // Clear the server ring before the Ctrl-L redraw output lands,
            // so the ring ends up holding just the fresh prompt.
            await client.clearScrollback(sessionID: sessionID)
            attachment?.sendInput([0x0C])
        }
    }

    /// Sends text to the session's shell as if typed, without a trailing
    /// newline (used for snippet pasting). Mirrors the keystroke path:
    /// dropped during replay, and clears any attention state.
    func sendText(_ text: String) {
        guard !isReplaying, !text.isEmpty else { return }
        if needsAttention || claudeStatus != .none {
            clearAttention()
        }
        attachment?.sendInput(Array(text.utf8))
    }

    /// Forces a full repaint of the terminal from its buffer. The engine
    /// only invalidates rows that changed and won't redraw on becoming
    /// visible, so a tab whose backing store was dropped while hidden can
    /// return blank. Called when a tab becomes selected.
    func forceRedraw() {
        emulator.redraw()
    }

    init(sessionID: SessionInfo.ID, client: SessionServerClient) {
        self.sessionID = sessionID
        self.client = client
        emulator = GhosttyEmulator()
        emulator.delegate = self
        // The Ghostty backend only parses bytes once its render surface
        // exists; when it appears, re-attach so the server replays scrollback
        // into the now-live surface.
        emulator.onSurfaceReady = { [weak self] in
            self?.attach()
        }
        configureScanner()
    }

    /// Routes attention sequences from the raw stream into controller state.
    /// The replay guards mirror the live/replay handling the emulator
    /// callbacks used to do.
    private func configureScanner() {
        scanner.onTitle = { [weak self] title in
            self?.shellTitle = title.isEmpty ? nil : title
        }
        scanner.onCwd = { [weak self] payload in
            self?.noteCwd(payload)
        }
        scanner.onBell = { [weak self] in
            guard let self, !isReplaying else { return }
            // Historical BELs still in the scrollback re-fire during replay
            // (badging a tab on every app start); only live bells count.
            hasBell = true
        }
        scanner.onNotification = { [weak self] payload in
            self?.noteNotification(message: payload)
        }
    }

    private func noteCwd(_ payload: String) {
        guard let path = Self.parseOSC7Path(payload) else { return }
        currentDirectory = path
        // During replay, historical OSC 7 sequences fire this repeatedly;
        // record locally and report once on replayDone instead of spamming
        // the socket. Live updates are forwarded immediately.
        if !isReplaying {
            reportCwdIfChanged()
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
            // Full terminal reset before the replay arrives.
            emulator.reset()
            scanner.reset()
            let attachment: SessionAttachment?
            attachment = try? await client.attach(
                sessionID: sessionID,
                cols: emulator.cols,
                rows: emulator.rows
            )
            guard let attachment else {
                Self.logger.error("Failed to attach session \(self.sessionID)")
                return
            }
            self.attachment = attachment
            // Reconcile the PTY size with the emulator's current grid. The
            // attach was requested with whatever size was known when it
            // started (often the pre-surface default), and any resize that
            // fired during the async handshake hit a nil/stale attachment and
            // was dropped. Without this the server PTY can stay at the wrong
            // width, so the shell wraps at a different column than the terminal
            // renders — corrupting wrapped-line editing.
            attachment.resize(cols: emulator.cols, rows: emulator.rows)
            for await event in attachment.events {
                switch event {
                case .replayStarted:
                    isReplaying = true
                case .output(let chunk):
                    // Attention parsing runs for every session regardless of
                    // render-surface state; the emulator only renders when it
                    // has a surface (Ghostty drops bytes otherwise).
                    scanner.scan(chunk[...])
                    emulator.feed(chunk[...])
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

extension TerminalSessionController: TerminalEmulatorDelegate {

    func emulatorSend(_ bytes: ArraySlice<UInt8>) {
        guard !isReplaying else { return }
        // The user is interacting with this tab; attention is served and
        // any Claude status badge (incl. working/done) is stale.
        if needsAttention || claudeStatus != .none {
            clearAttention()
        }
        attachment?.sendInput(Array(bytes))
    }

    func emulatorResized(cols: Int, rows: Int) {
        attachment?.resize(cols: cols, rows: rows)
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

    func emulatorOpenLink(_ link: String) {
        if let url = URL(string: link) {
            NSWorkspace.shared.open(url)
        }
    }

    func emulatorCopy(_ content: Data) {
        if let string = String(bytes: content, encoding: .utf8) {
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(string, forType: .string)
        }
    }
}
