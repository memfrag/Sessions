//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog
import SessionsIPC
import SessionsProtocol

/// The session server: accepts client connections, owns all sessions and
/// the persisted workspace/tab layout, and routes messages.
public actor ServerCore {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "ServerCore")

    private let listener: UnixSocketListener

    private let store: StateStore

    private let serverVersion: String

    private var state: ServerState

    private var sessions: [UUID: SessionActor] = [:]

    private var clients: [UnixSocketConnection] = []

    public init(
        socketPath: String,
        statePath: String,
        serverVersion: String,
        peerPolicy: PeerPolicy = .sameUserOnly
    ) throws {
        listener = try UnixSocketListener(path: socketPath, peerPolicy: peerPolicy)
        store = StateStore(path: statePath)
        self.serverVersion = serverVersion
        let loadedState = store.load()
        state = loadedState
        Self.logger.info("Server started on \(socketPath), \(loadedState.workspaces.count) workspaces")
    }

    /// Accepts connections until the listener closes.
    public func run() async {
        // Materialize session actors for every persisted session (dead).
        for workspace in state.workspaces {
            for session in workspace.sessions {
                materializeSession(id: session.id)
            }
        }
        for await connection in listener.connections {
            addClient(connection)
        }
    }

    /// Persists state and exits the process.
    public func persistAndExit(code: Int32) {
        store.save(state)
        for session in sessions.values {
            // Best effort: SIGHUP so shells die cleanly with the server.
            Task {
                await session.kill()
            }
        }
        Self.logger.info("Server exiting with code \(code)")
        // Give the kill tasks a beat to deliver SIGHUP, then exit.
        usleep(100_000)
        exit(code)
    }

    // MARK: - Clients

    private func addClient(_ connection: UnixSocketConnection) {
        clients.append(connection)
        Task {
            for await frame in connection.frames {
                await handle(frame, from: connection)
            }
            await removeClient(connection)
        }
    }

    private func removeClient(_ connection: UnixSocketConnection) async {
        clients.removeAll { $0 === connection }
        for session in sessions.values {
            await session.detachIfAttached(to: connection)
        }
        connection.close()
    }

    private func broadcastState() {
        for client in clients {
            client.send(.control(.stateChanged(state)))
        }
    }

    private func persistAndBroadcast() {
        store.save(state)
        broadcastState()
    }

    // MARK: - Message routing

    private func handle(_ frame: Frame, from connection: UnixSocketConnection) async {
        switch frame {
        case .input(let sessionID, let bytes):
            await sessions[sessionID]?.write(bytes)
        case .output:
            // Clients do not send output frames; ignore.
            break
        case .control(let message):
            await handle(message, from: connection)
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func handle(_ message: ControlMessage, from connection: UnixSocketConnection) async {
        switch message {
        case .clientHello(let protocolVersion, let appVersion):
            if protocolVersion == SessionsProtocolInfo.version {
                connection.send(.control(.serverHello(
                    protocolVersion: SessionsProtocolInfo.version,
                    serverVersion: serverVersion,
                    state: state
                )))
            } else {
                Self.logger.warning("Protocol mismatch: app \(appVersion) speaks \(protocolVersion)")
                connection.send(.control(.protocolMismatch(serverProtocolVersion: SessionsProtocolInfo.version)))
            }
        case .restartServer:
            persistAndExit(code: 1)
        case .shutdown:
            persistAndExit(code: 0)
        case .createWorkspace(let name, let rootPath):
            let workspace = Workspace(name: name, rootPath: rootPath)
            state.workspaces.append(workspace)
            persistAndBroadcast()
            // A workspace starts with one live tab.
            await createSession(
                workspaceID: workspace.id,
                inheritFromSessionID: nil,
                connection: connection
            )
        case .renameWorkspace(let id, let name):
            guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
            state.workspaces[index].name = name
            persistAndBroadcast()
        case .deleteWorkspace(let id):
            guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
            for session in state.workspaces[index].sessions {
                await removeSessionActor(id: session.id)
            }
            state.workspaces.remove(at: index)
            persistAndBroadcast()
        case .moveWorkspace(let id, let toIndex):
            guard let index = state.workspaces.firstIndex(where: { $0.id == id }) else { return }
            let workspace = state.workspaces.remove(at: index)
            state.workspaces.insert(workspace, at: min(max(0, toIndex), state.workspaces.count))
            persistAndBroadcast()
        case .createSession(let workspaceID, let inheritFromSessionID):
            await createSession(
                workspaceID: workspaceID,
                inheritFromSessionID: inheritFromSessionID,
                connection: connection
            )
        case .closeSession(let id):
            await removeSessionActor(id: id)
            removeSessionFromState(id: id)
            persistAndBroadcast()
        case .closeAllSessions:
            for id in sessions.keys {
                await removeSessionActor(id: id)
            }
            for index in state.workspaces.indices {
                state.workspaces[index].sessions.removeAll()
            }
            persistAndBroadcast()
        case .renameSession(let id, let customTitle):
            updateSession(id: id) { $0.customTitle = customTitle }
            persistAndBroadcast()
        case .restartSession(let id):
            await restartSession(id: id, connection: connection)
        case .moveSession(let id, let toIndex):
            guard let workspaceIndex = state.workspaces.firstIndex(where: { workspace in
                workspace.sessions.contains { $0.id == id }
            }) else { return }
            var sessionList = state.workspaces[workspaceIndex].sessions
            guard let sessionIndex = sessionList.firstIndex(where: { $0.id == id }) else { return }
            let session = sessionList.remove(at: sessionIndex)
            sessionList.insert(session, at: min(max(0, toIndex), sessionList.count))
            state.workspaces[workspaceIndex].sessions = sessionList
            persistAndBroadcast()
        case .sessionCwdChanged(let sessionID, let path):
            await sessions[sessionID]?.noteClientReportedCwd(path)
        case .checkBusy(let sessionID):
            let isBusy = await sessions[sessionID]?.isBusy() ?? false
            connection.send(.control(.busyStatus(sessionID: sessionID, isBusy: isBusy)))
        case .attach(let sessionID, let cols, let rows):
            guard let session = sessions[sessionID] else {
                connection.send(.control(.error(code: .unknownSession, message: "No session \(sessionID)")))
                return
            }
            await session.attach(connection: connection, cols: cols, rows: rows)
        case .detach(let sessionID):
            await sessions[sessionID]?.detach(connection: connection)
        case .resize(let sessionID, let cols, let rows):
            await sessions[sessionID]?.resize(cols: cols, rows: rows)
        case .serverHello, .protocolMismatch, .stateChanged, .attached, .replayDone,
             .sessionExited, .busyStatus, .error, .unknownMessage:
            // Server → client messages (or unknown payloads from newer
            // peers); ignored.
            break
        }
    }

    // MARK: - Sessions

    @discardableResult
    private func materializeSession(id: UUID) -> SessionActor {
        if let existing = sessions[id] {
            return existing
        }
        let session = SessionActor(id: id, serverVersion: serverVersion) { [weak self] sessionID, exitCode in
            Task {
                await self?.sessionDidExit(id: sessionID, exitCode: exitCode)
            }
        }
        sessions[id] = session
        return session
    }

    private func sessionDidExit(id: UUID, exitCode: Int32?) {
        updateSession(id: id) { session in
            session.isAlive = false
            session.exitCode = exitCode ?? -1
        }
        broadcastState()
    }

    private func createSession(
        workspaceID: UUID,
        inheritFromSessionID: UUID?,
        connection: UnixSocketConnection
    ) async {
        guard let workspaceIndex = state.workspaces.firstIndex(where: { $0.id == workspaceID }) else {
            connection.send(.control(.error(code: .unknownWorkspace, message: "No workspace \(workspaceID)")))
            return
        }
        let workspace = state.workspaces[workspaceIndex]
        var directory: String?
        if let inheritFromSessionID, let inheritFrom = sessions[inheritFromSessionID] {
            directory = await inheritFrom.currentWorkingDirectory()
        }
        let resolved = resolveDirectory(preferred: directory, workspace: workspace)
        let info = SessionInfo(isAlive: true)
        let session = materializeSession(id: info.id)
        do {
            try await session.spawn(currentDirectory: resolved)
        } catch {
            sessions[info.id] = nil
            connection.send(.control(.error(code: .spawnFailed, message: "\(error)")))
            return
        }
        state.workspaces[workspaceIndex].sessions.append(info)
        persistAndBroadcast()
    }

    private func restartSession(id: UUID, connection: UnixSocketConnection) async {
        guard let located = state.session(withID: id) else {
            connection.send(.control(.error(code: .unknownSession, message: "No session \(id)")))
            return
        }
        let session = materializeSession(id: id)
        guard await !session.isAlive else { return }
        let resolved = resolveDirectory(preferred: nil, workspace: located.workspace)
        do {
            try await session.spawn(currentDirectory: resolved)
        } catch {
            connection.send(.control(.error(code: .spawnFailed, message: "\(error)")))
            return
        }
        updateSession(id: id) { sessionInfo in
            sessionInfo.isAlive = true
            sessionInfo.exitCode = nil
        }
        persistAndBroadcast()
    }

    private func resolveDirectory(preferred: String?, workspace: Workspace) -> String {
        let fileManager = FileManager.default
        var isDirectory = ObjCBool(false)
        if let preferred,
           fileManager.fileExists(atPath: preferred, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return preferred
        }
        if fileManager.fileExists(atPath: workspace.rootPath, isDirectory: &isDirectory),
           isDirectory.boolValue {
            return workspace.rootPath
        }
        return NSHomeDirectory()
    }

    private func removeSessionActor(id: UUID) async {
        if let session = sessions[id] {
            await session.kill()
        }
        sessions[id] = nil
    }

    private func removeSessionFromState(id: UUID) {
        for index in state.workspaces.indices {
            state.workspaces[index].sessions.removeAll { $0.id == id }
        }
    }

    private func updateSession(id: UUID, _ mutate: (inout SessionInfo) -> Void) {
        for workspaceIndex in state.workspaces.indices {
            if let sessionIndex = state.workspaces[workspaceIndex].sessions.firstIndex(where: { $0.id == id }) {
                mutate(&state.workspaces[workspaceIndex].sessions[sessionIndex])
                return
            }
        }
    }
}
