//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import KeyValueStore

// MARK: - AppSettings

/// A container for application-wide user settings.
///
/// `AppSettings` provides observable properties that represent user preferences
/// and persists them using an underlying key–value store.
/// It is designed to be injected into SwiftUI views and other components
/// that depend on reactive settings.
///
@Observable @MainActor public final class AppSettings {

    // MARK: Key

    /// The keys used to store and retrieve settings from the underlying store.
    public enum Key: String {
        /// The preferred color scheme for the app.
        case colorScheme

        /// Terminal font size in points.
        case terminalFontSize

        /// Terminal color theme ID.
        case terminalThemeID

        /// Terminal font family name; empty means the system monospaced
        /// font (SF Mono).
        case terminalFontName

        /// Whether to use SwiftTerm's experimental Metal renderer.
        case useMetalRenderer

        // <-- (1 / 3) Add key for new property here
    }

    // MARK: Properties

    /// The app's current color scheme preference.
    public var colorScheme: AppColorScheme {
        didSet {
            store.save(colorScheme, for: .colorScheme)
        }
    }

    /// Terminal font size in points.
    public var terminalFontSize: Double {
        didSet {
            store.save(terminalFontSize, for: .terminalFontSize)
        }
    }

    /// Terminal color theme ID.
    public var terminalThemeID: String {
        didSet {
            store.save(terminalThemeID, for: .terminalThemeID)
        }
    }

    /// Terminal font family name; empty means the system monospaced font.
    public var terminalFontName: String {
        didSet {
            store.save(terminalFontName, for: .terminalFontName)
        }
    }

    /// Whether to use SwiftTerm's experimental Metal renderer.
    public var useMetalRenderer: Bool {
        didSet {
            store.save(useMetalRenderer, for: .useMetalRenderer)
        }
    }

    // <-- (2 / 3) Add property for new property here

    // MARK: Setup

    /// The key–value store that backs this settings container.
    @ObservationIgnored
    private let store: AnyKeyValueStore<AppSettings.Key>

    /// Creates a new instance of `AppSettings`.
    ///
    /// - Parameter store: The store used to persist values. If `nil`,
    ///   defaults to a `UserDefaults`-backed store.
    ///
    public init(store: AnyKeyValueStore<AppSettings.Key>? = nil) {
        self.store = store ?? .defaultStore
        colorScheme = self.store.load(.colorScheme, default: .system)
        terminalFontSize = self.store.load(.terminalFontSize, default: 13)
        terminalThemeID = self.store.load(.terminalThemeID, default: "system")
        terminalFontName = self.store.load(.terminalFontName, default: "")
        useMetalRenderer = self.store.load(.useMetalRenderer, default: false)

        // <-- (3 / 3) Add initializer for new property here.
    }
}
