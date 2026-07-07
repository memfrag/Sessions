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

    let terminalView: TerminalView

    private let client: SessionServerClient

    private var attachment: SessionAttachment?

    private var pumpTask: Task<Void, Never>?

    /// Title reported by the shell via OSC escape sequences, if any.
    private(set) var shellTitle: String?

    /// Mirrored from the server's `SessionInfo`.
    private(set) var isAlive = false

    private(set) var exitCode: Int32?

    /// A BEL arrived while this tab was in the background.
    private(set) var hasBell = false

    /// While the server replays scrollback, the terminal re-parses old
    /// query sequences (e.g. Device Attributes) and generates responses.
    /// Those queries were answered when they originally arrived, so all
    /// terminal→host traffic is dropped until `replayDone` — otherwise
    /// the responses land at the shell prompt as garbage input.
    private var isReplaying = false

    init(sessionID: SessionInfo.ID, client: SessionServerClient) {
        self.sessionID = sessionID
        self.client = client
        terminalView = TerminalView(frame: NSRect(x: 0, y: 0, width: 800, height: 600))
        terminalView.terminalDelegate = self
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

    func clearBell() {
        hasBell = false
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
        attachment?.sendInput(Array(data))
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        attachment?.resize(cols: newCols, rows: newRows)
    }

    func setTerminalTitle(source: TerminalView, title: String) {
        shellTitle = title.isEmpty ? nil : title
    }

    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {
        // The server resolves cwd inheritance via the PTY; nothing needed.
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
