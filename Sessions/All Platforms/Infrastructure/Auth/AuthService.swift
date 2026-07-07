//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import OSLog

enum AuthState {
    case notAuthenticated
    case authenticatedAnonymously(token: String)
    case authenticatedUser(token: String)

    var token: String? {
        switch self {
        case .notAuthenticated:
            nil
        case .authenticatedAnonymously(let token):
            token
        case .authenticatedUser(let token):
            token
        }
    }

    /// Either authenticated anonymously or as user.
    var isAuthenticated: Bool {
        switch self {
        case .notAuthenticated:
            false
        case .authenticatedAnonymously:
            true
        case .authenticatedUser:
            true
        }
    }

    var isAuthenticatedAnonymously: Bool {
        switch self {
        case .notAuthenticated:
            false
        case .authenticatedAnonymously:
            true
        case .authenticatedUser:
            false
        }
    }

    var isAuthenticatedUser: Bool {
        switch self {
        case .notAuthenticated:
            false
        case .authenticatedAnonymously:
            false
        case .authenticatedUser:
            true
        }
    }
}

@Observable @MainActor class AuthService {

    private(set) var authState: AuthState = .notAuthenticated

    @ObservationIgnored
    private(set) var token: String?

    init() {}

    public func refreshTokenStatus() async throws {
        Logger.auth.trace("🔓 Refreshing token status...")

        // Does not actually do anything yet.

        // Sets auth state on completion.
        authState = .authenticatedAnonymously(token: "SOME_ANONYMOUS_TOKEN")
    }
}

// MARK: - Singleton

extension AuthService {
    /// When possible, use `@Environment(AuthService.self)` rather than
    /// accessing the `shared` property directly.
    static let shared = AuthService()
    
    static func mock() -> AuthService {
        AuthService()
    }
}
