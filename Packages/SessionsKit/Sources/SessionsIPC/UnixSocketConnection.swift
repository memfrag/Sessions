//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Dispatch
import Foundation
import SessionsProtocol
import Synchronization

/// A framed, bidirectional connection over a Unix domain socket.
///
/// Reads happen on a dispatch read source and are surfaced as an ordered
/// `AsyncStream` of frames. Writes are serialized on a dedicated queue;
/// `send` never blocks the caller. This class is the only concurrency-
/// delicate code in the IPC layer — everything else is actors.
public final class UnixSocketConnection: Sendable {

    private struct MutableState {
        var isClosed = false
        var pendingWriteBytes = 0
        var decoder = FrameDecoder()
    }

    private let fd: Int32

    private let state = Mutex(MutableState())

    private let readSource: DispatchSourceRead

    private let writeQueue: DispatchQueue

    /// Ordered stream of incoming frames. Finishes when the connection
    /// closes or the peer disconnects. Single consumer.
    public let frames: AsyncStream<Frame>

    private let framesContinuation: AsyncStream<Frame>.Continuation

    /// Bytes queued for writing but not yet handed to the kernel. Used by
    /// the server to apply backpressure to PTY reads.
    public var pendingWriteBytes: Int {
        state.withLock { $0.pendingWriteBytes }
    }

    /// Wraps an already-connected socket fd. Takes ownership of the fd.
    public init(fd: Int32) {
        self.fd = fd
        SocketAddress.setNonBlocking(fd)
        SocketAddress.setCloseOnExec(fd)
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        (frames, framesContinuation) = AsyncStream.makeStream()
        let readQueue = DispatchQueue(label: "io.apparata.sessions.socket.read")
        writeQueue = DispatchQueue(label: "io.apparata.sessions.socket.write")
        readSource = DispatchSource.makeReadSource(fileDescriptor: fd, queue: readQueue)
        readSource.setEventHandler { [weak self] in
            self?.handleReadable()
        }
        let capturedFd = fd
        let capturedWriteQueue = writeQueue
        readSource.setCancelHandler {
            // Close the fd only after any queued writes have drained/failed,
            // so the fd number cannot be reused out from under the writer.
            capturedWriteQueue.async {
                Darwin.close(capturedFd)
            }
        }
        readSource.activate()
    }

    /// Connects to a Unix socket path and wraps the connection.
    public static func connect(to path: String) throws -> UnixSocketConnection {
        UnixSocketConnection(fd: try SocketAddress.connect(to: path))
    }

    /// Enqueues a frame for writing. Silently drops frames once closed.
    public func send(_ frame: Frame) {
        guard let bytes = try? FrameEncoder.encode(frame) else {
            return
        }
        let shouldEnqueue: Bool = state.withLock { mutableState in
            guard !mutableState.isClosed else { return false }
            mutableState.pendingWriteBytes += bytes.count
            return true
        }
        guard shouldEnqueue else { return }
        writeQueue.async { [weak self] in
            guard let self else { return }
            self.blockingWriteAll(bytes)
            self.state.withLock { $0.pendingWriteBytes -= bytes.count }
        }
    }

    /// Closes the connection. Idempotent.
    public func close() {
        let wasClosed = state.withLock { mutableState in
            let wasClosed = mutableState.isClosed
            mutableState.isClosed = true
            return wasClosed
        }
        guard !wasClosed else { return }
        shutdown(fd, SHUT_RDWR)
        readSource.cancel()
        framesContinuation.finish()
    }

    // MARK: - Reading

    private func handleReadable() {
        var buffer = [UInt8](repeating: 0, count: 65536)
        while true {
            let count = buffer.withUnsafeMutableBytes { pointer in
                read(fd, pointer.baseAddress, pointer.count)
            }
            if count > 0 {
                let decoded: [Frame]?
                decoded = try? state.withLock { mutableState in
                    try mutableState.decoder.append(buffer[0..<count])
                }
                guard let decoded else {
                    // Malformed stream: drop the connection.
                    close()
                    return
                }
                for frame in decoded {
                    framesContinuation.yield(frame)
                }
            } else if count == 0 {
                // EOF: peer closed.
                close()
                return
            } else {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK {
                    return
                }
                if error == EINTR {
                    continue
                }
                close()
                return
            }
        }
    }

    // MARK: - Writing

    private func blockingWriteAll(_ bytes: [UInt8]) {
        var offset = 0
        while offset < bytes.count {
            let isClosed = state.withLock { $0.isClosed }
            if isClosed {
                return
            }
            let written = bytes.withUnsafeBytes { pointer in
                write(fd, pointer.baseAddress?.advanced(by: offset), bytes.count - offset)
            }
            if written > 0 {
                offset += written
            } else {
                let error = errno
                if error == EAGAIN || error == EWOULDBLOCK {
                    var pollFd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
                    _ = poll(&pollFd, 1, 100)
                    continue
                }
                if error == EINTR {
                    continue
                }
                // EPIPE or worse: connection is dead.
                close()
                return
            }
        }
    }
}
