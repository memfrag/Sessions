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
            .closeAllSessions
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

    @Test func encoderRejectsOversizedFrames() {
        let bytes = [UInt8](repeating: 0, count: FrameCodecConstants.maxFrameLength + 1)
        #expect(throws: FrameCodecError.self) {
            _ = try FrameEncoder.encode(.output(sessionID: UUID(), bytes: bytes))
        }
    }
}
