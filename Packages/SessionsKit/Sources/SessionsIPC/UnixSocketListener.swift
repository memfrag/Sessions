//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Dispatch
import Foundation
import Synchronization

/// Listens on a Unix domain socket and surfaces accepted connections.
///
/// Only peers with the same UID as this process are accepted. The socket
/// file is created with mode 0600.
public final class UnixSocketListener: Sendable {

    private let fd: Int32

    private let path: String

    private let acceptSource: DispatchSourceRead

    private let isClosed = Mutex(false)

    /// Accepted connections. Finishes when the listener closes.
    public let connections: AsyncStream<UnixSocketConnection>

    private let connectionsContinuation: AsyncStream<UnixSocketConnection>.Continuation

    /// Binds and listens on `path`.
    ///
    /// If the socket file exists, probes it: a successful connect means
    /// another server is running (throws `alreadyRunning`); a refused
    /// connect means it is stale and is removed before binding.
    public init(path: String) throws {
        let directory = (path as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        if FileManager.default.fileExists(atPath: path) {
            if let probeFd = try? SocketAddress.connect(to: path) {
                Darwin.close(probeFd)
                throw UnixSocketError.alreadyRunning(path: path)
            }
            unlink(path)
        }
        let listenerFd = try SocketAddress.makeSocket()
        let bindResult = try SocketAddress.withSockaddrUn(path: path) { address, length in
            Darwin.bind(listenerFd, address, length)
        }
        guard bindResult == 0 else {
            let savedErrno = errno
            Darwin.close(listenerFd)
            throw UnixSocketError.bindFailed(errno: savedErrno)
        }
        chmod(path, 0o600)
        guard listen(listenerFd, 8) == 0 else {
            let savedErrno = errno
            Darwin.close(listenerFd)
            unlink(path)
            throw UnixSocketError.listenFailed(errno: savedErrno)
        }
        fd = listenerFd
        self.path = path
        (connections, connectionsContinuation) = AsyncStream.makeStream()
        let queue = DispatchQueue(label: "io.apparata.sessions.socket.accept")
        acceptSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        let capturedFd = fd
        acceptSource.setEventHandler { [weak self] in
            self?.handleAcceptable()
        }
        acceptSource.setCancelHandler {
            Darwin.close(capturedFd)
        }
        acceptSource.activate()
    }

    public func close() {
        let wasClosed = isClosed.withLock { closed in
            let wasClosed = closed
            closed = true
            return wasClosed
        }
        guard !wasClosed else { return }
        acceptSource.cancel()
        connectionsContinuation.finish()
        unlink(path)
    }

    private func handleAcceptable() {
        while true {
            let clientFd = accept(fd, nil, nil)
            if clientFd < 0 {
                return
            }
            guard let peerUID = SocketAddress.peerUID(of: clientFd), peerUID == getuid() else {
                Darwin.close(clientFd)
                continue
            }
            connectionsContinuation.yield(UnixSocketConnection(fd: clientFd))
        }
    }
}
