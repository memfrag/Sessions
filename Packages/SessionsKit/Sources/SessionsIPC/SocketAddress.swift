//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Foundation

public enum UnixSocketError: Error {
    case pathTooLong(String)
    case socketFailed(errno: Int32)
    case bindFailed(errno: Int32)
    case listenFailed(errno: Int32)
    case connectFailed(errno: Int32)
    case alreadyRunning(path: String)
}

enum SocketAddress {

    /// Calls `body` with a `sockaddr` pointer for the given Unix socket path.
    static func withSockaddrUn<R>(
        path: String,
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> R
    ) throws -> R {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(path.utf8)
        let capacity = MemoryLayout.size(ofValue: address.sun_path) - 1
        guard pathBytes.count <= capacity else {
            throw UnixSocketError.pathTooLong(path)
        }
        withUnsafeMutableBytes(of: &address.sun_path) { sunPath in
            for (index, byte) in pathBytes.enumerated() {
                sunPath[index] = byte
            }
            sunPath[pathBytes.count] = 0
        }
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        let length = socklen_t(MemoryLayout<sockaddr_un>.size)
        return try withUnsafePointer(to: &address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                try body(sockaddrPointer, length)
            }
        }
    }

    /// Creates a non-blocking `AF_UNIX` stream socket.
    static func makeSocket() throws -> Int32 {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw UnixSocketError.socketFailed(errno: errno)
        }
        setNonBlocking(fd)
        setCloseOnExec(fd)
        // Avoid SIGPIPE on writes to a closed peer; handle EPIPE instead.
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        return fd
    }

    static func setNonBlocking(_ fd: Int32) {
        let flags = fcntl(fd, F_GETFL, 0)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    }

    static func setCloseOnExec(_ fd: Int32) {
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    /// Returns the UID of the peer connected on a Unix socket.
    static func peerUID(of fd: Int32) -> uid_t? {
        var credentials = xucred()
        var length = socklen_t(MemoryLayout<xucred>.size)
        let result = getsockopt(fd, SOL_LOCAL, LOCAL_PEERCRED, &credentials, &length)
        guard result == 0, credentials.cr_version == UInt32(XUCRED_VERSION) else {
            return nil
        }
        return credentials.cr_uid
    }

    /// Synchronously connects to a Unix socket path.
    ///
    /// Returns the connected fd, or throws. Used both by the client and by
    /// the server's stale-socket probe.
    static func connect(to path: String) throws -> Int32 {
        let fd = try makeSocket()
        let result = try withSockaddrUn(path: path) { address, length in
            Darwin.connect(fd, address, length)
        }
        if result == 0 {
            return fd
        }
        // Non-blocking connect on a Unix socket either succeeds immediately
        // or fails; EINPROGRESS is not expected for AF_UNIX, but handle it
        // by polling for writability.
        if errno == EINPROGRESS {
            var pollFd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
            if poll(&pollFd, 1, 1000) == 1 {
                var socketError: Int32 = 0
                var errorLength = socklen_t(MemoryLayout<Int32>.size)
                getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &errorLength)
                if socketError == 0 {
                    return fd
                }
                Darwin.close(fd)
                throw UnixSocketError.connectFailed(errno: socketError)
            }
        }
        let savedErrno = errno
        Darwin.close(fd)
        throw UnixSocketError.connectFailed(errno: savedErrno)
    }
}
