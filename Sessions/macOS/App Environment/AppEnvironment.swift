//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import SwiftUI
import AppRouting

/// An application-wide environment container.
///
/// This type centralizes access to shared app state and dependencies that are safe to
/// read from anywhere in the app, such as `AppSettings`. Prefer injecting instances via
/// SwiftUI's `@Environment`.
///
/// Use ``AppEnvironment/shared`` for the process-global environment that is created
/// lazily at launch based on build configuration and the `APP_ENVIRONMENT` process
/// environment variable.
///
/// - Important: Avoid creating your own instances unless you are writing previews or tests.
///
public final class AppEnvironment {

    // MARK: - Properties

    /// Application settings used throughout the app.
    public let appSettings: AppSettings
    
    /// Auth service
    internal let authService: AuthService
    
    /// Engineering mode
    internal let engineeringMode: EngineeringMode

    // MARK: - Init

    /// Creates an environment with the provided dependencies.
    ///
    /// - Parameters:
    ///    - appSettings: The application settings to expose.
    /// - Note: Use ``live()``/``mock()`` rather than this initializer.
    ///
    internal init(
        appSettings: AppSettings,
        authService: AuthService,
        engineeringMode: EngineeringMode
    ) {
        self.appSettings = appSettings
        self.authService = authService
        self.engineeringMode = engineeringMode
    }
}
