//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// Engine-independent scanner for the attention-relevant escape sequences in
/// the raw server byte stream: OSC 0/2 (title), OSC 7 (working directory),
/// OSC 9 (notifications / Claude hooks), and a standalone BEL.
///
/// Sessions drives tab attention (bell, Claude badges, cwd, title) from this
/// scanner rather than from the render engine, because the Ghostty backend
/// only parses bytes once a render surface exists — background/never-mounted
/// tabs would otherwise stop lighting badges. Scanning the stream in the
/// controller keeps attention working for every session regardless of whether
/// its view is on screen.
///
/// The scanner is a small state machine so it survives chunk boundaries
/// (state persists across `scan` calls) and does not mistake a BEL that
/// terminates an OSC/DCS string for an audible bell.
@MainActor
final class TerminalStreamScanner {

    /// OSC 0/2 title payload.
    var onTitle: ((String) -> Void)?

    /// Raw OSC 7 working-directory payload (e.g. `file://host/path`).
    var onCwd: ((String) -> Void)?

    /// Raw OSC 9 notification payload (`nil` when empty).
    var onNotification: ((String?) -> Void)?

    /// A standalone BEL (0x07) that was not an OSC/string terminator.
    var onBell: (() -> Void)?

    private enum State {
        case normal
        case escape       // saw ESC in normal text
        case osc          // collecting an OSC payload (ESC ] …)
        case oscEscape    // saw ESC inside an OSC (possible ST terminator)
        case string       // opaque DCS/SOS/PM/APC string (skip until ST/BEL)
        case stringEscape // saw ESC inside such a string
    }

    private var state: State = .normal
    private var oscBuffer: [UInt8] = []

    /// Cap the OSC buffer so a pathological/huge payload (e.g. an OSC 52
    /// clipboard blob we don't dispatch anyway) can't grow unbounded. The
    /// code and the sequences we care about (title/cwd/claude) are tiny.
    private static let maxOSCLength = 8192

    func scan(_ bytes: ArraySlice<UInt8>) {
        for byte in bytes {
            switch state {
            case .normal:
                if byte == 0x1B {
                    state = .escape
                } else if byte == 0x07 {
                    onBell?()
                }

            case .escape:
                switch byte {
                case 0x5D: // ']' → OSC
                    oscBuffer.removeAll(keepingCapacity: true)
                    state = .osc
                case 0x50, 0x58, 0x5E, 0x5F: // P X ^ _ → DCS/SOS/PM/APC string
                    state = .string
                case 0x1B: // another ESC; keep waiting
                    state = .escape
                default: // CSI and other short escapes carry no BEL/OSC we track
                    state = .normal
                }

            case .osc:
                switch byte {
                case 0x07: // BEL terminator
                    dispatchOSC()
                    state = .normal
                case 0x1B: // possible ST (ESC \)
                    state = .oscEscape
                default:
                    if oscBuffer.count < Self.maxOSCLength {
                        oscBuffer.append(byte)
                    }
                }

            case .oscEscape:
                switch byte {
                case 0x5C: // '\' → ST terminator
                    dispatchOSC()
                    state = .normal
                case 0x1B: // still waiting for ST
                    state = .oscEscape
                default: // malformed; drop the partial OSC
                    oscBuffer.removeAll(keepingCapacity: true)
                    state = .normal
                }

            case .string:
                if byte == 0x07 {
                    state = .normal
                } else if byte == 0x1B {
                    state = .stringEscape
                }

            case .stringEscape:
                switch byte {
                case 0x5C: state = .normal // ST
                case 0x1B: state = .stringEscape
                default: state = .string
                }
            }
        }
    }

    /// Resets the parser state. Sequences don't span an attach, so the
    /// controller resets before replaying a fresh stream.
    func reset() {
        state = .normal
        oscBuffer.removeAll(keepingCapacity: true)
    }

    private func dispatchOSC() {
        defer { oscBuffer.removeAll(keepingCapacity: true) }
        // Payload is "code;rest"; a code with no ';' carries nothing we track.
        guard let semi = oscBuffer.firstIndex(of: 0x3B) else { return }
        guard let code = String(bytes: oscBuffer[..<semi], encoding: .utf8) else { return }
        let rest = String(bytes: oscBuffer[(semi + 1)...], encoding: .utf8) ?? ""
        switch code {
        case "0", "2":
            onTitle?(rest)
        case "7":
            onCwd?(rest)
        case "9":
            onNotification?(rest.isEmpty ? nil : rest)
        default:
            break
        }
    }
}
