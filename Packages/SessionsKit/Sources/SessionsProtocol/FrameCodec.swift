//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Encodes frames to wire bytes.
public enum FrameEncoder {

    public static func encode(_ frame: Frame) throws -> [UInt8] {
        let type: FrameType
        let body: [UInt8]
        switch frame {
        case .control(let message):
            type = .control
            body = try [UInt8](JSONEncoder().encode(message))
        case .output(let sessionID, let bytes):
            type = .output
            body = uuidBytes(sessionID) + bytes
        case .input(let sessionID, let bytes):
            type = .input
            body = uuidBytes(sessionID) + bytes
        }
        let length = body.count + 1
        guard length <= FrameCodecConstants.maxFrameLength else {
            throw FrameCodecError.frameTooLarge(length)
        }
        var result = [UInt8]()
        result.reserveCapacity(4 + length)
        result.append(UInt8((length >> 24) & 0xFF))
        result.append(UInt8((length >> 16) & 0xFF))
        result.append(UInt8((length >> 8) & 0xFF))
        result.append(UInt8(length & 0xFF))
        result.append(type.rawValue)
        result.append(contentsOf: body)
        return result
    }

    static func uuidBytes(_ uuid: UUID) -> [UInt8] {
        let u = uuid.uuid
        return [u.0, u.1, u.2, u.3, u.4, u.5, u.6, u.7, u.8, u.9, u.10, u.11, u.12, u.13, u.14, u.15]
    }
}

/// Incremental frame parser. Feed it bytes as they arrive; it emits every
/// complete frame and buffers the remainder.
///
/// Not thread-safe; confine each instance to one reader.
public struct FrameDecoder: Sendable {

    private var buffer: [UInt8] = []

    public init() {}

    public mutating func append(_ bytes: some Sequence<UInt8>) throws -> [Frame] {
        buffer.append(contentsOf: bytes)
        var frames: [Frame] = []
        while true {
            guard buffer.count >= 4 else { break }
            let length = (Int(buffer[0]) << 24) | (Int(buffer[1]) << 16) | (Int(buffer[2]) << 8) | Int(buffer[3])
            guard length >= 1 else {
                throw FrameCodecError.malformedFrame
            }
            guard length <= FrameCodecConstants.maxFrameLength else {
                throw FrameCodecError.frameTooLarge(length)
            }
            guard buffer.count >= 4 + length else { break }
            let typeByte = buffer[4]
            let body = Array(buffer[5..<(4 + length)])
            buffer.removeFirst(4 + length)
            frames.append(try Self.decodeFrame(typeByte: typeByte, body: body))
        }
        return frames
    }

    private static func decodeFrame(typeByte: UInt8, body: [UInt8]) throws -> Frame {
        guard let type = FrameType(rawValue: typeByte) else {
            throw FrameCodecError.unknownFrameType(typeByte)
        }
        switch type {
        case .control:
            do {
                let message = try JSONDecoder().decode(ControlMessage.self, from: Data(body))
                return .control(message)
            } catch {
                // Control frames are length-delimited, so an undecodable
                // payload cannot desync the stream. Mapping it to
                // `.unknownMessage` (instead of dropping the connection)
                // makes additive protocol changes non-breaking. Genuinely
                // corrupt JSON also lands here — acceptable.
                return .control(.unknownMessage)
            }
        case .output, .input:
            guard body.count >= 16 else {
                throw FrameCodecError.malformedFrame
            }
            let sessionID = uuidFromBytes(Array(body[0..<16]))
            let bytes = Array(body[16...])
            return type == .output
                ? .output(sessionID: sessionID, bytes: bytes)
                : .input(sessionID: sessionID, bytes: bytes)
        }
    }

    static func uuidFromBytes(_ b: [UInt8]) -> UUID {
        UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
                    b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
    }
}
