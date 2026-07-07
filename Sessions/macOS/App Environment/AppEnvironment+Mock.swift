//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import AppRouting

extension AppEnvironment {

    // MARK: - Mock AppEnvironment

    #if DEBUG
    /// Builds a mock environment configured for development and preview usage.
    ///
    /// Available only in `DEBUG` builds.
    ///
    /// - Returns: A new ``AppEnvironment`` instance with mocked dependencies.
    ///
    internal static func mock() -> AppEnvironment {
        AppEnvironment(
            appSettings: AppSettings.mock(),
            authService: AuthService.mock(),
            engineeringMode: EngineeringMode.shared
        )
    }
    #endif
}
