//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import AppRouting

// MARK: - View Extension

extension View {

    /// Applies the shared application environment to the view.
    ///
    /// This modifier injects key environment values into the view hierarchy,
    /// including:
    /// - The meta routing environment for `MainRouting`
    /// - The application's meta router instance
    /// - The application settings
    ///
    /// Use this on your root view to ensure all child views have access to
    /// the necessary environment objects for routing and configuration.
    ///
    /// - Parameter appEnvironment: The `AppEnvironment` containing shared
    ///   objects such as routing and settings.
    /// - Returns: A modified view with the application environment applied.
    ///
    func appEnvironment(_ appEnvironment: AppEnvironment) -> some View {
        self
            .environment(appEnvironment.appSettings)
            .environment(appEnvironment.authService)
            .environment(appEnvironment.engineeringMode)
    }
    
    #if DEBUG
    func previewEnvironment() -> some View {
        let appEnvironment = AppEnvironment.mock()
        return self
            .environment(appEnvironment.appSettings)
            .environment(appEnvironment.authService)
            .environment(appEnvironment.engineeringMode)
    }
    #endif
}
