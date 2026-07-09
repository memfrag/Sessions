//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Darwin
import Foundation
import OSLog
import Security

/// Who may connect to the server socket. Same-UID is always required
/// (enforced via `LOCAL_PEERCRED` before this policy runs).
public enum PeerPolicy: Sendable {

    /// Any process of the same user (tmux-style trust model). Used by
    /// tests and available for dev servers.
    case sameUserOnly

    /// Additionally require the connecting process to have a valid code
    /// signature whose identifier matches (cmux-style). `identifiers`
    /// match exactly; `identifierPrefixes` cover ad-hoc signatures with
    /// per-build hash suffixes (e.g. "sessions-server-<hash>"). If
    /// `teamID` is set, the peer's team identifier must match too —
    /// ad-hoc identifiers alone are forgeable, so release builds should
    /// pin the Developer ID team.
    case signedClients(identifiers: [String], identifierPrefixes: [String], teamID: String?)

    /// The policy a client uses to verify that the peer on the other end
    /// of the socket really is the sessions-server binary — the mirror
    /// image of the server verifying its clients. Same-user malware could
    /// otherwise squat the socket path and impersonate the server (and
    /// receive every keystroke). The team is pinned to this process's own
    /// signing team: nil for ad-hoc dev builds (identifier-only), the real
    /// team for Developer ID builds (unforgeable).
    public static func trustedSessionsServer() -> PeerPolicy {
        .signedClients(
            identifiers: ["sessions-server"],
            identifierPrefixes: ["sessions-server-"],
            teamID: PeerVerifier.ownTeamIdentifier()
        )
    }
}

/// Verifies connecting peers against a `PeerPolicy` using the socket's
/// audit token (`LOCAL_PEERTOKEN`), which — unlike PID-based checks — is
/// immune to PID-reuse races.
public enum PeerVerifier {

    private static let logger = Logger(subsystem: "io.apparata.Sessions", category: "PeerVerifier")

    /// `LOCAL_PEERTOKEN` from <sys/un.h>; not exposed to Swift.
    private static let localPeerToken: Int32 = 0x006

    /// This process's own code-signing team identifier, or nil if the
    /// build is ad-hoc / unsigned (development). Release builds signed
    /// with Developer ID return the signing team (e.g. Apparata's), which
    /// the server pins so only same-team binaries may connect.
    public static func ownTeamIdentifier() -> String? {
        var code: SecCode?
        guard SecCodeCopySelf([], &code) == errSecSuccess, let code else {
            return nil
        }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess,
              let staticCode else {
            return nil
        }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(staticCode, [], &info) == errSecSuccess,
              let dictionary = info as? [CFString: Any] else {
            return nil
        }
        return dictionary[kSecCodeInfoTeamIdentifier] as? String
    }

    static func isAuthorized(fd: Int32, policy: PeerPolicy) -> Bool {
        switch policy {
        case .sameUserOnly:
            return true
        case .signedClients(let identifiers, let prefixes, let teamID):
            guard let token = peerAuditToken(of: fd) else {
                logger.error("Rejecting peer: no audit token")
                return false
            }
            guard let (identifier, peerTeamID) = signingInfo(for: token) else {
                logger.error("Rejecting peer: unsigned or invalid signature")
                return false
            }
            let identifierMatches = identifiers.contains(identifier)
                || prefixes.contains { identifier.hasPrefix($0) }
            guard identifierMatches else {
                logger.error("Rejecting peer with identifier \(identifier)")
                return false
            }
            if let teamID {
                guard peerTeamID == teamID else {
                    logger.error("Rejecting peer with team \(peerTeamID ?? "none")")
                    return false
                }
            }
            return true
        }
    }

    private static func peerAuditToken(of fd: Int32) -> audit_token_t? {
        var token = audit_token_t()
        var length = socklen_t(MemoryLayout<audit_token_t>.size)
        let result = getsockopt(fd, SOL_LOCAL, localPeerToken, &token, &length)
        guard result == 0, length == socklen_t(MemoryLayout<audit_token_t>.size) else {
            return nil
        }
        return token
    }

    /// Validates the peer's code signature and returns its signing
    /// identifier and team identifier.
    private static func signingInfo(for token: audit_token_t) -> (identifier: String, teamID: String?)? {
        var tokenCopy = token
        let tokenData = withUnsafeBytes(of: &tokenCopy) { Data($0) }
        let attributes = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(nil, attributes, [], &code) == errSecSuccess,
              let code else {
            return nil
        }
        // Deliberately NO SecCodeCheckValidity here: it compares the
        // running process against its on-disk executable and fails with
        // errSecCSStaticCodeChanged (-67034) once the binary has been
        // replaced — but "the binary was updated while the old process
        // keeps running" is a scenario this app is designed to survive
        // (the server outlives rebuilds and app updates). The signing
        // identifier and team below come from the kernel-cached code
        // directory of the RUNNING image, which the kernel validated at
        // exec and a peer cannot spoof; that is exactly what the policy
        // pins.
        //
        // Interrogate the DYNAMIC code object, never a static-code
        // conversion (same on-disk problem). The C API accepts a
        // SecCodeRef wherever a SecStaticCodeRef is expected; only
        // Swift's imported signature is narrower, hence the cast.
        let codeAsStatic = unsafeBitCast(code, to: SecStaticCode.self)
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(codeAsStatic, [], &info) == errSecSuccess,
              let dictionary = info as? [CFString: Any],
              let identifier = dictionary[kSecCodeInfoIdentifier] as? String else {
            return nil
        }
        let teamID = dictionary[kSecCodeInfoTeamIdentifier] as? String
        return (identifier, teamID)
    }
}
