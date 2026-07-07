//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// One frame on the wire.
///
/// Wire format: `u32 length (big-endian) | u8 type | body`, where `length`
/// counts the type byte plus the body. Output/input bodies are a 16-byte
/// session UUID followed by raw bytes; control bodies are JSON.
public enum Frame: Sendable, Equatable {

    /// JSON-encoded ``ControlMessage``.
    case control(ControlMessage)

    /// PTY output, server → client.
    case output(sessionID: UUID, bytes: [UInt8])

    /// Keyboard/paste input, client → server.
    case input(sessionID: UUID, bytes: [UInt8])
}

public enum FrameType: UInt8 {
    case control = 0x00
    case output = 0x01
    case input = 0x02
}

public enum FrameCodecConstants {
    /// Sanity limit for a single frame's length field.
    public static let maxFrameLength = 1_048_576 + 17
}

public enum FrameCodecError: Error, Equatable {
    case frameTooLarge(Int)
    case unknownFrameType(UInt8)
    case malformedFrame
}
