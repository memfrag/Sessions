//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Testing
@testable import SessionsProtocol

struct FrameCodecTests {

    @Test func controlRoundTrip() throws {
        let state = ServerState(workspaces: [
            Workspace(name: "Test", rootPath: "/tmp", sessions: [
                SessionInfo(customTitle: "Tab 1", isAlive: true)
            ])
        ])
        let messages: [ControlMessage] = [
            .clientHello(protocolVersion: 1, appVersion: "1.0"),
            .serverHello(protocolVersion: 1, serverVersion: "1.0", state: state),
            .createSession(workspaceID: UUID(), inheritFromSessionID: UUID()),
            .createSession(workspaceID: UUID(), inheritFromSessionID: nil),
            .attach(sessionID: UUID(), cols: 120, rows: 40),
            .sessionExited(sessionID: UUID(), exitCode: 137),
            .error(code: .spawnFailed, message: "nope"),
            .closeAllSessions,
            .sessionCwdChanged(sessionID: UUID(), path: "/tmp/with space/ünïcode/dir"),
            .unknownMessage
        ]
        for message in messages {
            let encoded = try FrameEncoder.encode(.control(message))
            var decoder = FrameDecoder()
            let frames = try decoder.append(encoded)
            #expect(frames == [.control(message)])
        }
    }

    @Test func outputInputRoundTrip() throws {
        let id = UUID()
        let bytes: [UInt8] = Array("hello \u{1B}[31mworld\u{1B}[0m".utf8)
        var decoder = FrameDecoder()
        let outputFrames = try decoder.append(try FrameEncoder.encode(.output(sessionID: id, bytes: bytes)))
        #expect(outputFrames == [.output(sessionID: id, bytes: bytes)])
        let inputFrames = try decoder.append(try FrameEncoder.encode(.input(sessionID: id, bytes: bytes)))
        #expect(inputFrames == [.input(sessionID: id, bytes: bytes)])
    }

    @Test func emptyOutputBody() throws {
        let id = UUID()
        var decoder = FrameDecoder()
        let frames = try decoder.append(try FrameEncoder.encode(.output(sessionID: id, bytes: [])))
        #expect(frames == [.output(sessionID: id, bytes: [])])
    }

    @Test func incrementalParsingAcrossArbitrarySplits() throws {
        let id = UUID()
        var wire: [UInt8] = []
        var expected: [Frame] = []
        for index in 0..<20 {
            let frame = Frame.output(sessionID: id, bytes: Array("chunk-\(index)".utf8))
            expected.append(frame)
            wire.append(contentsOf: try FrameEncoder.encode(frame))
        }
        // Fixed seed for reproducibility: split the stream at pseudo-random points.
        var seed: UInt64 = 0x5EED
        func nextSplit(max maxValue: Int) -> Int {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Int(seed % UInt64(maxValue)) + 1
        }
        var decoder = FrameDecoder()
        var decoded: [Frame] = []
        var offset = 0
        while offset < wire.count {
            let chunkLength = min(nextSplit(max: 13), wire.count - offset)
            decoded.append(contentsOf: try decoder.append(wire[offset..<(offset + chunkLength)]))
            offset += chunkLength
        }
        #expect(decoded == expected)
    }

    @Test func oversizedFrameIsRejected() throws {
        let tooBig = FrameCodecConstants.maxFrameLength + 1
        var header: [UInt8] = [
            UInt8((tooBig >> 24) & 0xFF),
            UInt8((tooBig >> 16) & 0xFF),
            UInt8((tooBig >> 8) & 0xFF),
            UInt8(tooBig & 0xFF)
        ]
        header.append(FrameType.output.rawValue)
        var decoder = FrameDecoder()
        #expect(throws: FrameCodecError.frameTooLarge(tooBig)) {
            _ = try decoder.append(header)
        }
    }

    @Test func unknownFrameTypeIsRejected() throws {
        let body: [UInt8] = [0xAB]
        var wire: [UInt8] = [0, 0, 0, 2, 0x7F]
        wire.append(contentsOf: body)
        var decoder = FrameDecoder()
        #expect(throws: FrameCodecError.unknownFrameType(0x7F)) {
            _ = try decoder.append(wire)
        }
    }

    @Test func truncatedUUIDBodyIsRejected() throws {
        // Output frame with a body shorter than a UUID.
        let wire: [UInt8] = [0, 0, 0, 5, FrameType.output.rawValue, 1, 2, 3, 4]
        var decoder = FrameDecoder()
        #expect(throws: FrameCodecError.malformedFrame) {
            _ = try decoder.append(wire)
        }
    }

    @Test func unknownControlPayloadDecodesAsUnknownMessage() throws {
        // A control message from a hypothetical future protocol version.
        let futureBody = Array(#"{"someFutureMessage":{"answer":42}}"#.utf8)
        let length = futureBody.count + 1
        var wire: [UInt8] = [
            UInt8((length >> 24) & 0xFF),
            UInt8((length >> 16) & 0xFF),
            UInt8((length >> 8) & 0xFF),
            UInt8(length & 0xFF),
            FrameType.control.rawValue
        ]
        wire.append(contentsOf: futureBody)
        // A valid frame following the unknown one must still decode:
        // the stream stays in sync because frames are length-delimited.
        let followUp = Frame.output(sessionID: UUID(), bytes: [1, 2, 3])
        wire.append(contentsOf: try FrameEncoder.encode(followUp))
        var decoder = FrameDecoder()
        let frames = try decoder.append(wire)
        #expect(frames == [.control(.unknownMessage), followUp])
    }

    @Test func encoderRejectsOversizedFrames() {
        let bytes = [UInt8](repeating: 0, count: FrameCodecConstants.maxFrameLength + 1)
        #expect(throws: FrameCodecError.self) {
            _ = try FrameEncoder.encode(.output(sessionID: UUID(), bytes: bytes))
        }
    }

    /// A v1.1-era `Workspace` JSON without the newer optional fields must
    /// keep decoding (old state.json files and old peers).
    @Test func workspaceDecodesWithoutNewerOptionalFields() throws {
        let json = """
        {"id":"11111111-2222-3333-4444-555555555555","name":"Old","rootPath":"/tmp","sessions":[]}
        """
        let workspace = try JSONDecoder().decode(Workspace.self, from: Data(json.utf8))
        #expect(workspace.name == "Old")
        #expect(workspace.startupCommand == nil)
        #expect(workspace.colorID == nil)
    }

    /// A `createWorkspace` frame from an old client (no startupCommand or
    /// colorID keys) must decode into the real case, not `.unknownMessage`.
    @Test func createWorkspaceDecodesWithoutNewerOptionalFields() throws {
        let payload = """
        {"createWorkspace":{"name":"Old","rootPath":"/tmp"}}
        """
        let message = try JSONDecoder().decode(ControlMessage.self, from: Data(payload.utf8))
        guard case .createWorkspace(let name, let rootPath, let startupCommand, let colorID) = message else {
            Issue.record("Expected createWorkspace, got \(message)")
            return
        }
        #expect(name == "Old")
        #expect(rootPath == "/tmp")
        #expect(startupCommand == nil)
        #expect(colorID == nil)
    }

    @Test func newWorkspaceMessagesRoundTrip() throws {
        let messages: [ControlMessage] = [
            .createWorkspace(name: "W", rootPath: "/tmp", startupCommand: "claude", colorID: "teal"),
            .updateWorkspace(id: UUID(), name: "W2", startupCommand: nil, colorID: "red")
        ]
        for message in messages {
            let encoded = try FrameEncoder.encode(.control(message))
            var decoder = FrameDecoder()
            let frames = try decoder.append(encoded)
            #expect(frames == [.control(message)])
        }
    }
}
