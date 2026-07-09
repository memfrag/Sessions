//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Testing
@testable import SessionsClient
@testable import SessionsProtocol
@testable import SessionsServerCore

/// End-to-end tests: a real ServerCore on a real Unix socket in a temp
/// directory, talked to by a real SessionServerClient, spawning real PTYs.
struct ServerEndToEndTests {

    private func makeTempPaths() -> (socket: String, state: String, directory: String) {
        // Keep the socket path short: sun_path is limited to ~104 bytes.
        let directory = "/tmp/sessions-test-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return ("\(directory)/s.sock", "\(directory)/state.json", directory)
    }

    private func startServer(socket: String, state: String) throws -> (ServerCore, Task<Void, Never>) {
        let core = try ServerCore(socketPath: socket, statePath: state, serverVersion: "test")
        let task = Task {
            await core.run()
        }
        return (core, task)
    }

    private func connectClient(socket: String) async throws -> (SessionServerClient, ServerState) {
        // The in-process ServerCore's peer is the test runner, not a
        // signed sessions-server binary, so server verification is off.
        let client = SessionServerClient(verifiesServerSignature: false)
        var lastError: (any Error)?
        for _ in 0..<50 {
            do {
                let state = try await client.connect(socketPath: socket, appVersion: "test")
                return (client, state)
            } catch {
                lastError = error
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        throw lastError ?? SessionServerClientError.notConnected
    }

    private func waitForState(
        _ client: SessionServerClient,
        timeout: Duration = .seconds(5),
        condition: @escaping (ServerState) -> Bool
    ) async -> ServerState? {
        let deadline = ContinuousClock.now + timeout
        for await event in client.events {
            if case .stateChanged(let state) = event, condition(state) {
                return state
            }
            if ContinuousClock.now > deadline {
                return nil
            }
        }
        return nil
    }

    @Test func handshakeAndWorkspaceCrud() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, initialState) = try await connectClient(socket: paths.socket)
        #expect(initialState.workspaces.isEmpty)

        await client.createWorkspace(name: "Alpha", rootPath: "/tmp")
        var state = await waitForState(client) { $0.workspaces.count == 1 }
        #expect(state?.workspaces.first?.name == "Alpha")

        let workspaceID = try #require(state?.workspaces.first?.id)
        await client.renameWorkspace(id: workspaceID, name: "Beta")
        state = await waitForState(client) { $0.workspaces.first?.name == "Beta" }
        #expect(state != nil)

        // Persistence: the state file exists and contains the workspace.
        let persisted = StateStore(path: paths.state).load()
        #expect(persisted.workspaces.first?.name == "Beta")
    }

    @Test func sessionSpawnEchoAndReplay() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { $0.workspaces.count == 1 }
        let workspaceID = try #require(state1?.workspaces.first?.id)

        await client.createSession(workspaceID: workspaceID, inheritFromSessionID: nil)
        let state2 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state2?.workspaces.first?.sessions.first)
        #expect(session.isAlive)

        // Attach and type a command; expect the echoed marker in output.
        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo MARKER-$((40 + 2))\n".utf8))
        var collected = [UInt8]()
        var sawMarker = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("MARKER-42") {
                sawMarker = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawMarker, "Expected shell echo output to contain MARKER-42")

        // Detach, re-attach: the replay must be bracketed by replayStarted/
        // replayDone and contain the marker again.
        await client.detach(sessionID: session.id)
        let reattachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        var replayed = [UInt8]()
        var sawReplayStarted = false
        var replaySawMarkerBeforeDone = false
        let replayDeadline = ContinuousClock.now + .seconds(10)
        for await event in reattachment.events {
            switch event {
            case .replayStarted:
                sawReplayStarted = true
            case .output(let chunk):
                replayed.append(contentsOf: chunk)
            case .replayDone:
                replaySawMarkerBeforeDone = String(decoding: replayed, as: UTF8.self).contains("MARKER-42")
            }
            if replaySawMarkerBeforeDone || ContinuousClock.now > replayDeadline {
                break
            }
        }
        #expect(sawReplayStarted, "Expected a replayStarted event on re-attach")
        #expect(replaySawMarkerBeforeDone, "Expected scrollback replay to contain MARKER-42 before replayDone")
    }

    @Test func sessionExitIsReportedAndRestartable() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { $0.workspaces.count == 1 }
        let workspaceID = try #require(state1?.workspaces.first?.id)
        await client.createSession(workspaceID: workspaceID, inheritFromSessionID: nil)
        let state2 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state2?.workspaces.first?.sessions.first)

        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        attachment.sendInput(Array("exit 3\n".utf8))
        // Wait for the state to reflect the exit.
        let exitedState = await waitForState(client) { state in
            state.workspaces.first?.sessions.first.map { !$0.isAlive && $0.exitCode != nil } ?? false
        }
        #expect(exitedState?.workspaces.first?.sessions.first?.exitCode == 3)

        // Restart: session becomes alive again.
        await client.restartSession(id: session.id)
        let restartedState = await waitForState(client) { state in
            state.workspaces.first?.sessions.first?.isAlive ?? false
        }
        #expect(restartedState != nil)
    }

    @Test func degenerateResizeDoesNotCrashServer() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state?.workspaces.first?.sessions.first)
        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)

        // Out-of-range sizes (negative, zero, > UInt16.max) previously
        // trapped in PtyProcess.resize and killed the whole server.
        attachment.resize(cols: -5, rows: -1)
        attachment.resize(cols: 0, rows: 0)
        attachment.resize(cols: 100_000, rows: 99_999)
        try await Task.sleep(for: .milliseconds(300))

        // The server must still be alive: a normal resize + echo still works.
        attachment.resize(cols: 80, rows: 24)
        attachment.sendInput(Array("echo STILL-ALIVE\n".utf8))
        var collected = [UInt8]()
        var alive = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("STILL-ALIVE") {
                alive = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(alive, "Server should survive out-of-range resizes")
    }

    @Test func cwdInheritancePrefersClientReported() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let workspaceID = try #require(state1?.workspaces.first?.id)
        let sessionA = try #require(state1?.workspaces.first?.sessions.first)

        // Report a distinctive existing directory as session A's cwd.
        let reportedDir = "\(paths.directory)/reported dir"
        try FileManager.default.createDirectory(atPath: reportedDir, withIntermediateDirectories: true)
        await client.reportCwd(sessionID: sessionA.id, path: reportedDir)
        // Small pause so the fire-and-forget report lands before createSession.
        try await Task.sleep(for: .milliseconds(200))

        await client.createSession(workspaceID: workspaceID, inheritFromSessionID: sessionA.id)
        let state2 = await waitForState(client) { state in
            (state.workspaces.first?.sessions.count ?? 0) >= 2
        }
        let newSession = try #require(state2?.workspaces.first?.sessions.last)
        #expect(newSession.id != sessionA.id)

        let attachment = try await client.attach(sessionID: newSession.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo CWD-$PWD-DONE\n".utf8))
        var collected = [UInt8]()
        var sawReported = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            // /tmp may resolve to /private/tmp; match on the unique suffix.
            if String(decoding: collected, as: UTF8.self).contains("reported dir-DONE") {
                sawReported = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawReported, "New session should start in the client-reported cwd")
    }

    @Test func cwdInheritanceFallsBackWhenReportedPathMissing() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let workspaceID = try #require(state1?.workspaces.first?.id)
        let sessionA = try #require(state1?.workspaces.first?.sessions.first)

        await client.reportCwd(sessionID: sessionA.id, path: "/nonexistent/bogus/dir")
        try await Task.sleep(for: .milliseconds(200))
        await client.createSession(workspaceID: workspaceID, inheritFromSessionID: sessionA.id)
        let state2 = await waitForState(client) { state in
            (state.workspaces.first?.sessions.count ?? 0) >= 2
        }
        let newSession = try #require(state2?.workspaces.first?.sessions.last)

        let attachment = try await client.attach(sessionID: newSession.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo CWD-$PWD-DONE\n".utf8))
        var collected = [UInt8]()
        var text = ""
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            text = String(decoding: collected, as: UTF8.self)
            if text.contains("-DONE") && text.contains("CWD-/") {
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(!text.contains("bogus"), "Bogus reported cwd must not be used")
    }

    @Test func termProgramEnvironmentIsSet() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state1?.workspaces.first?.sessions.first)
        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo PROG-$TERM_PROGRAM-END\n".utf8))
        var collected = [UInt8]()
        var sawProgram = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("PROG-Sessions-END") {
                sawProgram = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawProgram, "Shell should see TERM_PROGRAM=Sessions")
    }

    @Test func busyCheckDetectsForegroundProcess() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client) { $0.workspaces.count == 1 }
        let workspaceID = try #require(state1?.workspaces.first?.id)
        await client.createSession(workspaceID: workspaceID, inheritFromSessionID: nil)
        let state2 = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state2?.workspaces.first?.sessions.first)
        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)

        // Give the shell a moment to start, then check idle state.
        // Drain output in the background so nothing blocks.
        let drainTask = Task {
            for await _ in attachment.events {}
        }
        defer { drainTask.cancel() }
        try await Task.sleep(for: .seconds(1))
        let idleBusy = await client.checkBusy(sessionID: session.id)
        #expect(!idleBusy, "Idle shell should not be busy")

        attachment.sendInput(Array("sleep 30\n".utf8))
        try await Task.sleep(for: .seconds(1))
        let busy = await client.checkBusy(sessionID: session.id)
        #expect(busy, "Shell running sleep should be busy")
    }

    /// The workspace startup command is typed into new tabs' shells
    /// (queued as typeahead right after spawn, consumed at first prompt),
    /// and must NOT run again when a session is restarted.
    @Test func startupCommandRunsInNewTabsButNotOnRestart() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(
            name: "Work",
            rootPath: "/tmp",
            startupCommand: "echo STARTUP-$((100 + 23))",
            colorID: "teal"
        )
        // The workspace auto-creates one tab; the startup command runs there.
        let state = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        #expect(state?.workspaces.first?.startupCommand == "echo STARTUP-$((100 + 23))")
        #expect(state?.workspaces.first?.colorID == "teal")
        let session = try #require(state?.workspaces.first?.sessions.first)

        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        var collected = [UInt8]()
        var sawStartupMarker = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("STARTUP-123") {
                sawStartupMarker = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawStartupMarker, "Expected the startup command output STARTUP-123 in the new tab")

        // Exit the shell and restart the session: the startup command must
        // not run again (only the one echo from the original spawn is in
        // the scrollback).
        attachment.sendInput(Array("exit\n".utf8))
        _ = await waitForState(client) { state in
            state.workspaces.first?.sessions.first.map { !$0.isAlive } ?? false
        }
        await client.restartSession(id: session.id)
        _ = await waitForState(client) { state in
            state.workspaces.first?.sessions.first?.isAlive ?? false
        }
        await client.detach(sessionID: session.id)
        let reattachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        reattachment.sendInput(Array("echo PROBE-$((200 + 22))\n".utf8))
        var replayed = [UInt8]()
        var sawProbe = false
        let probeDeadline = ContinuousClock.now + .seconds(10)
        for await event in reattachment.events {
            if case .output(let chunk) = event {
                replayed.append(contentsOf: chunk)
            }
            if String(decoding: replayed, as: UTF8.self).contains("PROBE-222") {
                sawProbe = true
                break
            }
            if ContinuousClock.now > probeDeadline {
                break
            }
        }
        #expect(sawProbe)
        // At most one occurrence: the original run may appear in replayed
        // scrollback (once scrollback survives restarts), but a restart
        // must never run the command a second time.
        let text = String(decoding: replayed, as: UTF8.self)
        let startupRuns = text.components(separatedBy: "STARTUP-123").count - 1
        #expect(startupRuns <= 1, "Restart must not re-run the startup command; saw \(startupRuns) run(s)")
    }

    /// Moving a session to another workspace is a pure state move: the
    /// shell keeps running and I/O still flows afterwards.
    @Test func moveSessionBetweenWorkspacesKeepsShellAlive() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Source", rootPath: "/tmp")
        _ = await waitForState(client) { $0.workspaces.count == 1 }
        await client.createWorkspace(name: "Target", rootPath: "/tmp")
        let state1 = await waitForState(client) { $0.workspaces.count == 2 }
        let source = try #require(state1?.workspaces.first { $0.name == "Source" })
        let target = try #require(state1?.workspaces.first { $0.name == "Target" })
        let session = try #require(source.sessions.first)

        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        await client.moveSessionToWorkspace(id: session.id, workspaceID: target.id, toIndex: nil)
        let state2 = await waitForState(client) { state in
            state.workspace(withID: target.id)?.sessions.contains { $0.id == session.id } ?? false
        }
        let movedTarget = try #require(state2?.workspace(withID: target.id))
        #expect(movedTarget.sessions.last?.id == session.id)
        #expect(state2?.workspace(withID: source.id)?.sessions.isEmpty == true)
        #expect(movedTarget.sessions.first { $0.id == session.id }?.isAlive == true)

        // I/O still flows through the untouched attachment after the move.
        attachment.sendInput(Array("echo MOVED-$((500 + 1))\n".utf8))
        var collected = [UInt8]()
        var sawMarker = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("MOVED-501") {
                sawMarker = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawMarker, "Expected I/O to keep flowing after the move")

        // The move persists.
        let persisted = StateStore(path: paths.state).load()
        #expect(persisted.workspace(withID: target.id)?.sessions.contains { $0.id == session.id } == true)
    }

    /// updateWorkspace edits name, startup command, and color, and the
    /// changes survive a StateStore round trip.
    @Test func updateWorkspaceRoundTrip() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (_, serverTask) = try startServer(socket: paths.socket, state: paths.state)
        defer { serverTask.cancel() }
        let (client, _) = try await connectClient(socket: paths.socket)

        await client.createWorkspace(name: "Before", rootPath: "/tmp")
        let state1 = await waitForState(client) { $0.workspaces.count == 1 }
        let workspaceID = try #require(state1?.workspaces.first?.id)

        await client.updateWorkspace(
            id: workspaceID,
            name: "After",
            startupCommand: "npm run dev",
            colorID: "purple"
        )
        let state2 = await waitForState(client) { $0.workspaces.first?.name == "After" }
        #expect(state2?.workspaces.first?.startupCommand == "npm run dev")
        #expect(state2?.workspaces.first?.colorID == "purple")

        let persisted = StateStore(path: paths.state).load()
        #expect(persisted.workspaces.first?.name == "After")
        #expect(persisted.workspaces.first?.startupCommand == "npm run dev")
        #expect(persisted.workspaces.first?.colorID == "purple")
    }

    /// A verifying client must refuse a listener that is not a signed
    /// sessions-server binary. The in-process test server doubles as the
    /// impostor: the peer process on its socket is the test runner.
    @Test func clientRejectsUnsignedServerPeer() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (core, task) = try startServer(socket: paths.socket, state: paths.state)
        defer { task.cancel() }
        let client = SessionServerClient()
        var sawUntrustedServer = false
        for _ in 0..<50 {
            do {
                _ = try await client.connect(socketPath: paths.socket, appVersion: "test")
                break // Connected: verification failed to reject the peer.
            } catch SessionServerClientError.untrustedServer {
                sawUntrustedServer = true
                break
            } catch {
                // Server not listening yet; retry.
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        #expect(sawUntrustedServer, "Client should reject a peer that is not a signed sessions-server")
        _ = core
    }
}
