//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog
import SessionsIPC
import SessionsProtocol

public enum SessionServerClientError: Error {
    case notConnected
    case connectionClosed
    case protocolMismatch(serverProtocolVersion: Int)
    case handshakeFailed
}

/// Events surfaced to the app outside of per-session output.
public enum SessionServerEvent: Sendable {
    case stateChanged(ServerState)
    case sessionExited(sessionID: UUID, exitCode: Int32?)
    case detachedByOtherClient(sessionID: UUID?)
    case disconnected
}

/// The app's connection to the session server.
///
/// Owns the socket, performs the version handshake, routes output frames to
/// per-session attachment streams, and exposes server events.
public actor SessionServerClient {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "SessionServerClient")

    private var connection: UnixSocketConnection?

    private var readTask: Task<Void, Never>?

    private var helloContinuation: CheckedContinuation<ControlMessage, any Error>?

    private var busyContinuations: [UUID: CheckedContinuation<Bool, Never>] = [:]

    private var outputContinuations: [UUID: AsyncStream<[UInt8]>.Continuation] = [:]

    /// Server events. Single consumer (the app's server manager).
    public nonisolated let events: AsyncStream<SessionServerEvent>

    private let eventsContinuation: AsyncStream<SessionServerEvent>.Continuation

    public private(set) var isConnected = false

    public init() {
        (events, eventsContinuation) = AsyncStream.makeStream()
    }

    // MARK: - Connection

    /// Connects, performs the handshake, and returns the initial state.
    public func connect(socketPath: String, appVersion: String) async throws -> ServerState {
        disconnectInternal(notify: false)
        let connection = try UnixSocketConnection.connect(to: socketPath)
        self.connection = connection
        readTask = Task {
            // This task inherits the actor's isolation, so frame handling
            // is serialized with the rest of the client.
            for await frame in connection.frames {
                self.handle(frame)
            }
            self.handleConnectionClosed(connection)
        }
        connection.send(.control(.clientHello(
            protocolVersion: SessionsProtocolInfo.version,
            appVersion: appVersion
        )))
        let reply: ControlMessage = try await withCheckedThrowingContinuation { continuation in
            helloContinuation = continuation
        }
        switch reply {
        case .serverHello(_, _, let state):
            isConnected = true
            return state
        case .protocolMismatch(let serverProtocolVersion):
            disconnectInternal(notify: false)
            throw SessionServerClientError.protocolMismatch(serverProtocolVersion: serverProtocolVersion)
        default:
            disconnectInternal(notify: false)
            throw SessionServerClientError.handshakeFailed
        }
    }

    public func disconnect() {
        disconnectInternal(notify: false)
    }

    private func disconnectInternal(notify: Bool) {
        readTask?.cancel()
        readTask = nil
        connection?.close()
        connection = nil
        isConnected = false
        helloContinuation?.resume(throwing: SessionServerClientError.connectionClosed)
        helloContinuation = nil
        for continuation in busyContinuations.values {
            continuation.resume(returning: false)
        }
        busyContinuations.removeAll()
        for continuation in outputContinuations.values {
            continuation.finish()
        }
        outputContinuations.removeAll()
        if notify {
            eventsContinuation.yield(.disconnected)
        }
    }

    private func handleConnectionClosed(_ connection: UnixSocketConnection) {
        guard self.connection === connection else { return }
        disconnectInternal(notify: true)
    }

    // MARK: - Frame handling

    private func handle(_ frame: Frame) {
        switch frame {
        case .output(let sessionID, let bytes):
            outputContinuations[sessionID]?.yield(bytes)
        case .input:
            break
        case .control(let message):
            handle(message)
        }
    }

    private func handle(_ message: ControlMessage) {
        switch message {
        case .serverHello, .protocolMismatch:
            helloContinuation?.resume(returning: message)
            helloContinuation = nil
        case .stateChanged(let state):
            eventsContinuation.yield(.stateChanged(state))
        case .sessionExited(let sessionID, let exitCode):
            eventsContinuation.yield(.sessionExited(sessionID: sessionID, exitCode: exitCode))
        case .busyStatus(let sessionID, let isBusy):
            busyContinuations[sessionID]?.resume(returning: isBusy)
            busyContinuations[sessionID] = nil
        case .attached, .replayDone:
            // Replay boundaries; the terminal controller resets before
            // attaching, so no action is needed here.
            break
        case .error(let code, let message):
            Self.logger.error("Server error \(code.rawValue): \(message)")
            if code == .detachedByOtherClient {
                eventsContinuation.yield(.detachedByOtherClient(sessionID: nil))
            }
        default:
            break
        }
    }

    // MARK: - Attachment

    /// Attaches to a session. The server replies with the scrollback replay
    /// followed by live output, all on the handle's output stream.
    ///
    /// Any previous attachment stream for the session is finished.
    public func attach(sessionID: UUID, cols: Int, rows: Int) throws -> SessionAttachment {
        guard let connection, isConnected else {
            throw SessionServerClientError.notConnected
        }
        outputContinuations[sessionID]?.finish()
        let (stream, continuation) = AsyncStream<[UInt8]>.makeStream()
        outputContinuations[sessionID] = continuation
        connection.send(.control(.attach(sessionID: sessionID, cols: cols, rows: rows)))
        return SessionAttachment(sessionID: sessionID, connection: connection, output: stream)
    }

    public func detach(sessionID: UUID) {
        connection?.send(.control(.detach(sessionID: sessionID)))
        outputContinuations[sessionID]?.finish()
        outputContinuations[sessionID] = nil
    }

    // MARK: - Requests

    public func checkBusy(sessionID: UUID) async -> Bool {
        guard let connection, isConnected else { return false }
        if let pending = busyContinuations[sessionID] {
            pending.resume(returning: false)
            busyContinuations[sessionID] = nil
        }
        return await withCheckedContinuation { continuation in
            busyContinuations[sessionID] = continuation
            connection.send(.control(.checkBusy(sessionID: sessionID)))
        }
    }

    // MARK: - Commands (fire and forget; state comes back via stateChanged)

    public func send(_ message: ControlMessage) {
        connection?.send(.control(message))
    }

    public func createWorkspace(name: String, rootPath: String) {
        send(.createWorkspace(name: name, rootPath: rootPath))
    }

    public func renameWorkspace(id: UUID, name: String) {
        send(.renameWorkspace(id: id, name: name))
    }

    public func deleteWorkspace(id: UUID) {
        send(.deleteWorkspace(id: id))
    }

    public func moveWorkspace(id: UUID, toIndex: Int) {
        send(.moveWorkspace(id: id, toIndex: toIndex))
    }

    public func createSession(workspaceID: UUID, inheritFromSessionID: UUID?) {
        send(.createSession(workspaceID: workspaceID, inheritFromSessionID: inheritFromSessionID))
    }

    public func closeSession(id: UUID) {
        send(.closeSession(id: id))
    }

    public func closeAllSessions() {
        send(.closeAllSessions)
    }

    public func renameSession(id: UUID, customTitle: String?) {
        send(.renameSession(id: id, customTitle: customTitle))
    }

    public func restartSession(id: UUID) {
        send(.restartSession(id: id))
    }

    public func moveSession(id: UUID, toIndex: Int) {
        send(.moveSession(id: id, toIndex: toIndex))
    }

    public func requestServerRestart() {
        send(.restartServer)
    }

    public func requestServerShutdown() {
        send(.shutdown)
    }
}

/// Handle for one attached session.
///
/// Input and resize are synchronous sends on the connection's serial write
/// queue, so calling them in order from the main thread preserves byte order.
public struct SessionAttachment: Sendable {

    public let sessionID: UUID

    let connection: UnixSocketConnection

    /// Scrollback replay followed by live PTY output. Finishes on detach
    /// or disconnect.
    public let output: AsyncStream<[UInt8]>

    public func sendInput(_ bytes: [UInt8]) {
        connection.send(.input(sessionID: sessionID, bytes: bytes))
    }

    public func resize(cols: Int, rows: Int) {
        connection.send(.control(.resize(sessionID: sessionID, cols: cols, rows: rows)))
    }
}
