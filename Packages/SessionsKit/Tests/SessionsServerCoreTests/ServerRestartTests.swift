//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Testing
@testable import SessionsIPC
@testable import SessionsProtocol
@testable import SessionsServerCore

/// Reproduces the app's protocol-mismatch recovery path: a throwaway
/// connection that sends `.restartServer` without any handshake.
struct ServerRestartTests {

    @Test func throwawayConnectionDeliversRestartServer() async throws {
        let directory = "/tmp/sessions-restart-\(UUID().uuidString.prefix(8))"
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(atPath: directory) }
        let socketPath = "\(directory)/s.sock"

        // A ServerCore in-process would `exit()` the test runner on
        // restartServer, so observe the effect indirectly: route the
        // message through a raw listener that records what it decodes.
        let listener = try UnixSocketListener(path: socketPath)
        let received = AsyncStream<ControlMessage>.makeStream()
        let acceptTask = Task {
            for await serverSide in listener.connections {
                Task {
                    for await frame in serverSide.frames {
                        if case .control(let message) = frame {
                            received.continuation.yield(message)
                        }
                    }
                }
            }
        }
        defer {
            acceptTask.cancel()
            listener.close()
        }

        // Exactly what ServerManager.requestServerRestartAfterMismatch does.
        let connection = try UnixSocketConnection.connect(to: socketPath)
        connection.send(.control(.restartServer))
        try await Task.sleep(for: .milliseconds(200))
        connection.close()

        var sawRestart = false
        let deadline = ContinuousClock.now + .seconds(5)
        for await message in received.stream {
            if message == .restartServer {
                sawRestart = true
                break
            }
            if ContinuousClock.now > deadline {
                break
            }
        }
        #expect(sawRestart, "restartServer should arrive over a throwaway connection")
    }
}
