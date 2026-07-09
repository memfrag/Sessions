//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Testing
@testable import SessionsClient
@testable import SessionsProtocol
@testable import SessionsServerCore

/// Scrollback persistence across graceful server exits: a second server
/// booted on the same state directory replays the previous server's
/// scrollback for its (now dormant) sessions.
struct ScrollbackPersistenceTests {

    private func makeTempPaths() -> (directory: String, state: String) {
        let directory = "/tmp/sessions-sbtest-\(UUID().uuidString.prefix(8))"
        try? FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        return (directory, "\(directory)/state.json")
    }

    private func startServer(socket: String, state: String) throws -> (ServerCore, Task<Void, Never>) {
        let core = try ServerCore(socketPath: socket, statePath: state, serverVersion: "test")
        let task = Task {
            await core.run()
        }
        return (core, task)
    }

    private func connectClient(socket: String) async throws -> (SessionServerClient, ServerState) {
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

    /// Echo a marker, persist for shutdown, boot a second server on the
    /// same state directory: attaching to the dormant session must replay
    /// the marker.
    @Test func scrollbackSurvivesGracefulRestart() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (core1, task1) = try startServer(socket: "\(paths.directory)/s1.sock", state: paths.state)
        let (client1, _) = try await connectClient(socket: "\(paths.directory)/s1.sock")

        await client1.createWorkspace(name: "Work", rootPath: "/tmp")
        let state1 = await waitForState(client1) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state1?.workspaces.first?.sessions.first)

        let attachment = try await client1.attach(sessionID: session.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo PERSIST-$((900 + 1))\n".utf8))
        var collected = [UInt8]()
        var sawMarker = false
        let deadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("PERSIST-901") {
                sawMarker = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawMarker)

        // Graceful-exit persistence, WITHOUT the exit() (it would kill the
        // test runner). Then tear server1 down.
        await core1.persistForShutdown()
        await client1.disconnect()
        task1.cancel()

        // A .bin exists for the session.
        let scrollbackFile = "\(paths.directory)/scrollback/\(session.id.uuidString).bin"
        #expect(FileManager.default.fileExists(atPath: scrollbackFile))

        // Second server, same state dir, fresh socket. The session is
        // dormant (dead, no exit code) and replays the restored buffer.
        let (_, task2) = try startServer(socket: "\(paths.directory)/s2.sock", state: paths.state)
        defer { task2.cancel() }
        let (client2, bootState) = try await connectClient(socket: "\(paths.directory)/s2.sock")
        let restored = try #require(bootState.workspaces.first?.sessions.first)
        #expect(!restored.isAlive)
        #expect(restored.exitCode == nil)

        let reattachment = try await client2.attach(sessionID: restored.id, cols: 80, rows: 24)
        var replayed = [UInt8]()
        var replayContainedMarker = false
        let replayDeadline = ContinuousClock.now + .seconds(10)
        for await event in reattachment.events {
            switch event {
            case .replayStarted:
                break
            case .output(let chunk):
                replayed.append(contentsOf: chunk)
            case .replayDone:
                replayContainedMarker = String(decoding: replayed, as: UTF8.self).contains("PERSIST-901")
            }
            if replayContainedMarker || ContinuousClock.now > replayDeadline {
                break
            }
        }
        #expect(replayContainedMarker, "Expected restored scrollback to replay PERSIST-901 after a graceful restart")
    }

    /// Closing a session removes its persisted scrollback file.
    @Test func closeSessionDeletesScrollbackFile() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let (core, task) = try startServer(socket: "\(paths.directory)/s.sock", state: paths.state)
        defer { task.cancel() }
        let (client, _) = try await connectClient(socket: "\(paths.directory)/s.sock")

        await client.createWorkspace(name: "Work", rootPath: "/tmp")
        let state = await waitForState(client) { state in
            state.workspaces.first.map { !$0.sessions.isEmpty } ?? false
        }
        let session = try #require(state?.workspaces.first?.sessions.first)

        // Wait for actual shell output first: an empty ring persists no
        // file (save of empty bytes is a delete).
        let attachment = try await client.attach(sessionID: session.id, cols: 80, rows: 24)
        attachment.sendInput(Array("echo FILE-$((600 + 6))\n".utf8))
        var collected = [UInt8]()
        let outputDeadline = ContinuousClock.now + .seconds(10)
        for await event in attachment.events {
            if case .output(let chunk) = event {
                collected.append(contentsOf: chunk)
            }
            if String(decoding: collected, as: UTF8.self).contains("FILE-606")
                || ContinuousClock.now > outputDeadline {
                break
            }
        }

        await core.persistForShutdown()
        let scrollbackFile = "\(paths.directory)/scrollback/\(session.id.uuidString).bin"
        #expect(FileManager.default.fileExists(atPath: scrollbackFile))

        await client.closeSession(id: session.id)
        _ = await waitForState(client) { state in
            state.workspaces.first?.sessions.isEmpty ?? false
        }
        #expect(!FileManager.default.fileExists(atPath: scrollbackFile))
    }

    /// Booting garbage-collects scrollback files for sessions that no
    /// longer exist in the persisted layout.
    @Test func bootRemovesOrphanedScrollbackFiles() async throws {
        let paths = makeTempPaths()
        defer { try? FileManager.default.removeItem(atPath: paths.directory) }
        let scrollbackDirectory = "\(paths.directory)/scrollback"
        try FileManager.default.createDirectory(atPath: scrollbackDirectory, withIntermediateDirectories: true)
        let orphan = "\(scrollbackDirectory)/\(UUID().uuidString).bin"
        try Data("orphan".utf8).write(to: URL(filePath: orphan))

        let (_, task) = try startServer(socket: "\(paths.directory)/s.sock", state: paths.state)
        defer { task.cancel() }
        _ = try await connectClient(socket: "\(paths.directory)/s.sock")

        // GC runs at the start of run(); poll briefly for the deletion.
        let deadline = ContinuousClock.now + .seconds(5)
        while FileManager.default.fileExists(atPath: orphan), ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(20))
        }
        #expect(!FileManager.default.fileExists(atPath: orphan))
    }
}
