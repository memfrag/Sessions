//
//  Copyright © 2026 Apparata AB. All rights reserved.
//
//  THROWAWAY (DEBUG-only) spike for the libghostty-spm evaluation. Proves
//  an InMemoryTerminalSession renders end-to-end in-app, driven by a real
//  /bin/zsh over a local PTY (output → receive, input → PTY, resize →
//  TIOCSWINSZ). Not wired into the real session path. Delete when the
//  evaluation concludes.

#if DEBUG

import Darwin
import GhosttyTerminal
import SwiftUI

struct GhosttySpikeWindow: Scene {

    static let windowID = "ghostty-spike"

    var body: some Scene {
        Window("Ghostty Spike", id: Self.windowID) {
            GhosttySpikeView()
                .frame(minWidth: 600, minHeight: 380)
        }
        .commandsRemoved()
        .defaultSize(width: 760, height: 460)
    }
}

private struct GhosttySpikeView: View {

    @StateObject private var model = GhosttySpikeModel()

    var body: some View {
        VStack(spacing: 0) {
            TerminalSurfaceView(context: model.state)
            Divider()
            GhosttySpikeStatusBar(state: model.state)
        }
        .onAppear { model.start() }
    }
}

/// Observes the state container's published callbacks (title, bell, cwd,
/// OSC 9 body) so we can see them fire live. Must observe the
/// `TerminalViewState` directly — it's the object those @Published values
/// live on.
private struct GhosttySpikeStatusBar: View {

    @ObservedObject var state: TerminalViewState

    var body: some View {
        HStack(spacing: 16) {
            label("title", state.title)
            label("cwd", state.workingDirectory ?? "—")
            label("bell", "\(state.bellCount)")
            label("osc9", state.lastDesktopNotificationBody ?? "—")
        }
        .font(.caption.monospaced())
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func label(_ key: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(key).foregroundStyle(.secondary)
            Text(value)
        }
    }
}

@MainActor
private final class GhosttySpikeModel: ObservableObject {

    let state = TerminalViewState()

    private var session: InMemoryTerminalSession?

    private var masterFd: Int32 = -1

    private var shellPid: pid_t = -1

    private var readSource: DispatchSourceRead?

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        let session = InMemoryTerminalSession(
            write: { [weak self] data in
                Task { @MainActor in self?.writeToShell(data) }
            },
            resize: { [weak self] viewport in
                Task { @MainActor in
                    self?.resizeShell(cols: viewport.columns, rows: viewport.rows)
                }
            }
        )
        self.session = session
        state.configuration = TerminalSurfaceOptions(backend: .inMemory(session))
        spawnShell()
    }

    private func spawnShell() {
        var master: Int32 = 0
        var size = winsize(ws_row: 24, ws_col: 80, ws_xpixel: 0, ws_ypixel: 0)
        let pid = forkpty(&master, nil, nil, &size)
        if pid < 0 { return }
        if pid == 0 {
            // Child: only async-signal-safe calls until exec.
            setenv("TERM", "xterm-256color", 1)
            let args: [UnsafeMutablePointer<CChar>?] = [strdup("-zsh"), nil]
            execv("/bin/zsh", args)
            _exit(127)
        }
        shellPid = pid
        masterFd = master
        let source = DispatchSource.makeReadSource(fileDescriptor: master, queue: .main)
        source.setEventHandler { [weak self] in
            self?.readFromShell()
        }
        source.resume()
        readSource = source
    }

    private func readFromShell() {
        var buffer = [UInt8](repeating: 0, count: 8192)
        let count = buffer.withUnsafeMutableBytes { read(masterFd, $0.baseAddress, $0.count) }
        guard count > 0 else { return }
        session?.receive(Data(buffer[0..<count]))
    }

    private func writeToShell(_ data: Data) {
        guard masterFd >= 0 else { return }
        data.withUnsafeBytes { pointer in
            _ = write(masterFd, pointer.baseAddress, pointer.count)
        }
    }

    private func resizeShell(cols: UInt16, rows: UInt16) {
        guard masterFd >= 0, cols > 0, rows > 0 else { return }
        var size = winsize(ws_row: rows, ws_col: cols, ws_xpixel: 0, ws_ypixel: 0)
        _ = ioctl(masterFd, TIOCSWINSZ, &size)
    }

    deinit {
        readSource?.cancel()
        if shellPid > 0 { kill(shellPid, SIGHUP) }
        if masterFd >= 0 { close(masterFd) }
    }
}

#endif
