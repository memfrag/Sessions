//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Dispatch
import Foundation
import OSLog
import SessionsIPC
import SessionsProtocol

/// Owns one terminal session: its PTY process, scrollback ring buffer, and
/// the (single) attached client connection.
actor SessionActor {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "SessionActor")

    /// Ring buffer capacity per session.
    static let scrollbackCapacity = 2 * 1024 * 1024

    /// Pause PTY reads when the attached client has this much unsent data.
    static let backpressureThreshold = 4 * 1024 * 1024

    /// Replay chunk size.
    static let replayChunkSize = 65536

    nonisolated let id: UUID

    private var pty: PtyProcess?

    private var ring = RingBuffer(capacity: SessionActor.scrollbackCapacity)

    private var attachedConnection: UnixSocketConnection?

    private var readSource: DispatchSourceRead?

    /// Whether the read source is suspended for backpressure. A suspended
    /// dispatch source must be resumed before it is cancelled/released,
    /// or Dispatch traps.
    private var isReadSourceSuspended = false

    private var exitSource: DispatchSourceProcess?

    private var outputTask: Task<Void, Never>?

    private var cols = 80

    private var rows = 24

    private(set) var isAlive = false

    private(set) var exitCode: Int32?

    /// Called when the shell process exits. Set once by ServerCore.
    private let onExit: @Sendable (UUID, Int32?) -> Void

    private let serverVersion: String

    /// Working directory most recently reported by the client's terminal
    /// via OSC 7. Runtime-only; preferred over `proc_pidinfo` for new-tab
    /// cwd inheritance because it is exact and shell-driven.
    private var clientReportedCwd: String?

    init(id: UUID, serverVersion: String, onExit: @escaping @Sendable (UUID, Int32?) -> Void) {
        self.id = id
        self.serverVersion = serverVersion
        self.onExit = onExit
    }

    // MARK: - Spawning

    /// Spawns the user's login shell in the given directory.
    func spawn(currentDirectory: String) throws {
        guard !isAlive else { return }
        let shell = Self.loginShell()
        let shellName = (shell as NSString).lastPathComponent
        let pty = try PtyProcess(
            executable: shell,
            args: ["-\(shellName)"],
            environment: Self.childEnvironment(serverVersion: serverVersion),
            currentDirectory: currentDirectory,
            cols: cols,
            rows: rows
        )
        self.pty = pty
        isAlive = true
        exitCode = nil
        clientReportedCwd = nil
        // The ring is deliberately NOT cleared: a restarted shell's banner
        // appends after the previous content, and attach replays the whole
        // ring after a full reset — old context, then the fresh prompt.
        startReading(pty: pty)
        startExitWatcher(pty: pty)
        Self.logger.info("Spawned shell pid \(pty.pid) for session \(self.id)")
    }

    private static func loginShell() -> String {
        if let passwd = getpwuid(getuid()), let shell = passwd.pointee.pw_shell {
            let value = String(cString: shell)
            if !value.isEmpty {
                return value
            }
        }
        return ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
    }

    private static func childEnvironment(serverVersion: String) -> [String] {
        var result = [
            "TERM=xterm-256color",
            "COLORTERM=truecolor",
            "LANG=en_US.UTF-8",
            "TERM_PROGRAM=Sessions",
            "TERM_PROGRAM_VERSION=\(serverVersion)"
        ]
        let env = ProcessInfo.processInfo.environment
        for key in ["LOGNAME", "USER", "HOME", "TMPDIR"] {
            if let value = env[key] {
                result.append("\(key)=\(value)")
            }
        }
        result.append(contentsOf: shellIntegrationEnvironment(env: env))
        return result
    }

    /// Ghostty-style automatic zsh integration: point ZDOTDIR at the
    /// bundled shell-integration directory, whose .zshenv restores the
    /// user's real ZDOTDIR, chains their config, and loads the Sessions
    /// hooks (OSC 7 cwd reporting, Claude Code attention hooks). No-op
    /// when the resources are absent (e.g. `swift run` dev server).
    private static func shellIntegrationEnvironment(env: [String: String]) -> [String] {
        guard let resources = Bundle.main.resourceURL else { return [] }
        let directory = resources.appending(path: "ShellIntegration", directoryHint: .isDirectory)
        let directoryPath = directory.path(percentEncoded: false)
        guard FileManager.default.fileExists(atPath: directoryPath + "/.zshenv") else {
            return []
        }
        var result = [
            "ZDOTDIR=\(directoryPath)",
            "SESSIONS_INTEGRATION_DIR=\(directoryPath)",
            "SESSIONS_CLAUDE_HOOKS=\(directoryPath)/claude-hooks.json"
        ]
        if let original = env["ZDOTDIR"] {
            result.append("SESSIONS_ORIG_ZDOTDIR=\(original)")
        }
        return result
    }

    // MARK: - Output pump

    private func startReading(pty: PtyProcess) {
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
        let queue = DispatchQueue(label: "io.apparata.sessions.pty.read")
        let source = DispatchSource.makeReadSource(fileDescriptor: pty.masterFd, queue: queue)
        let fd = pty.masterFd
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: 65536)
            while true {
                let count = buffer.withUnsafeMutableBytes { pointer in
                    read(fd, pointer.baseAddress, pointer.count)
                }
                if count > 0 {
                    continuation.yield(Array(buffer[0..<count]))
                } else if count == 0 {
                    continuation.finish()
                    return
                } else {
                    let error = errno
                    if error == EAGAIN || error == EWOULDBLOCK {
                        return
                    }
                    if error == EINTR {
                        continue
                    }
                    // EIO: the child side closed (process exited).
                    continuation.finish()
                    return
                }
            }
        }
        source.activate()
        readSource = source
        outputTask = Task {
            for await chunk in stream {
                await self.handleOutput(chunk)
            }
        }
    }

    private func handleOutput(_ chunk: [UInt8]) async {
        ring.append(chunk)
        guard let connection = attachedConnection else { return }
        connection.send(.output(sessionID: id, bytes: chunk))
        // Backpressure: pause PTY reads while the client's write queue is
        // deep; the child process then blocks on write like on a real
        // terminal. Nothing is dropped.
        if connection.pendingWriteBytes > Self.backpressureThreshold, let source = readSource {
            source.suspend()
            isReadSourceSuspended = true
            while connection.pendingWriteBytes > Self.backpressureThreshold / 2 {
                try? await Task.sleep(for: .milliseconds(50))
                if attachedConnection !== connection {
                    break
                }
                // The session may have been torn down during the sleep
                // (actor reentrancy); teardown resumed the source already.
                if !isReadSourceSuspended {
                    return
                }
            }
            if isReadSourceSuspended {
                isReadSourceSuspended = false
                source.resume()
            }
        }
    }

    // MARK: - Exit watching

    private func startExitWatcher(pty: PtyProcess) {
        let source = DispatchSource.makeProcessSource(
            identifier: pty.pid,
            eventMask: .exit,
            queue: DispatchQueue(label: "io.apparata.sessions.pty.exit")
        )
        let pid = pty.pid
        source.setEventHandler { [weak self] in
            var status: Int32 = 0
            let result = waitpid(pid, &status, WNOHANG)
            var code: Int32?
            if result == pid {
                if status & 0x7F == 0 {
                    // WIFEXITED
                    code = (status >> 8) & 0xFF
                } else {
                    // Terminated by signal.
                    code = 128 + (status & 0x7F)
                }
            }
            let capturedCode = code
            Task { [weak self] in
                await self?.handleExit(code: capturedCode)
            }
        }
        source.activate()
        exitSource = source
    }

    private func handleExit(code: Int32?) {
        guard isAlive else { return }
        isAlive = false
        exitCode = code
        tearDownSources()
        pty?.closeMaster()
        pty = nil
        attachedConnection?.send(.control(.sessionExited(sessionID: id, exitCode: code)))
        Self.logger.info("Session \(self.id) exited with code \(code.map(String.init) ?? "nil")")
        onExit(id, code)
    }

    private func tearDownSources() {
        if isReadSourceSuspended {
            // Cancelling/releasing a suspended source traps in Dispatch.
            isReadSourceSuspended = false
            readSource?.resume()
        }
        readSource?.cancel()
        readSource = nil
        exitSource?.cancel()
        exitSource = nil
        outputTask?.cancel()
        outputTask = nil
    }

    // MARK: - Attachment

    /// Attaches a client: evicts any previous client, then replays the
    /// scrollback ring buffer followed by `replayDone`.
    func attach(connection: UnixSocketConnection, cols: Int, rows: Int) {
        if let previous = attachedConnection, previous !== connection {
            previous.send(.control(.error(
                code: .detachedByOtherClient,
                message: "Another client attached to session \(id)"
            )))
        }
        attachedConnection = connection
        let replay = ring.snapshot()
        connection.send(.control(.attached(sessionID: id, isAlive: isAlive, replayBytes: replay.count)))
        var offset = 0
        while offset < replay.count {
            let end = min(offset + Self.replayChunkSize, replay.count)
            connection.send(.output(sessionID: id, bytes: Array(replay[offset..<end])))
            offset = end
        }
        connection.send(.control(.replayDone(sessionID: id)))
        resize(cols: cols, rows: rows)
    }

    func detach(connection: UnixSocketConnection) {
        if attachedConnection === connection {
            attachedConnection = nil
        }
    }

    /// Detaches if this session is attached to the given connection
    /// (used when a client disconnects).
    func detachIfAttached(to connection: UnixSocketConnection) {
        detach(connection: connection)
    }

    // MARK: - Terminal I/O and control

    func write(_ bytes: [UInt8]) {
        guard let pty else { return }
        var offset = 0
        while offset < bytes.count {
            let written = bytes.withUnsafeBytes { pointer in
                Darwin.write(pty.masterFd, pointer.baseAddress?.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else if errno == EAGAIN || errno == EWOULDBLOCK {
                var pollFd = pollfd(fd: pty.masterFd, events: Int16(POLLOUT), revents: 0)
                _ = poll(&pollFd, 1, 100)
            } else if errno != EINTR {
                return
            }
        }
    }

    func resize(cols: Int, rows: Int) {
        self.cols = cols
        self.rows = rows
        pty?.resize(cols: cols, rows: rows)
    }

    func isBusy() -> Bool {
        pty?.isBusy() ?? false
    }

    /// Current scrollback contents, oldest first (for shutdown persistence).
    func scrollbackSnapshot() -> [UInt8] {
        ring.snapshot()
    }

    /// Discards the scrollback history so a later re-attach replays nothing
    /// (the client clears its own view separately).
    func clearScrollback() {
        ring.clear()
    }

    /// Seeds the ring with scrollback restored from disk. Only meaningful
    /// for a freshly materialized dead session with an empty ring.
    func preloadScrollback(_ bytes: [UInt8]) {
        guard !isAlive, ring.count == 0 else { return }
        ring.append(bytes)
    }

    func noteClientReportedCwd(_ path: String) {
        clientReportedCwd = path
    }

    /// Current working directory of the session, for cwd inheritance when
    /// opening a new tab. Prefers the client-reported OSC 7 directory (if
    /// it still exists), falling back to the foreground process's cwd.
    func currentWorkingDirectory() -> String? {
        if let reported = clientReportedCwd {
            var isDirectory = ObjCBool(false)
            if FileManager.default.fileExists(atPath: reported, isDirectory: &isDirectory),
               isDirectory.boolValue {
                return reported
            }
        }
        return pty?.foregroundWorkingDirectory()
    }

    /// Kills the shell (tab closed or workspace deleted). SIGHUP first;
    /// SIGKILL after a grace period if it lingers.
    func kill() {
        guard let pty else { return }
        pty.hangUp()
        let processGroupID = pty.shellProcessGroupID
        Task {
            try? await Task.sleep(for: .seconds(3))
            // Safe even if the process is already gone; killpg of a dead
            // group just fails with ESRCH.
            killpg(processGroupID, SIGKILL)
        }
    }
}
