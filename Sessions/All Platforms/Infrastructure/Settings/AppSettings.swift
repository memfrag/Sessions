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

        /// Whether the Option key acts as Meta (ESC prefix) instead of
        /// composing characters.
        case optionAsMetaKey

        /// Terminal scrollback buffer size in lines.
        case terminalScrollbackLines

        /// Terminal tab stop width in columns.
        case terminalTabStopWidth

        /// Terminal cursor shape: "block", "underline", or "bar".
        case terminalCursorShape

        /// Whether the terminal cursor blinks.
        case terminalCursorBlinks

        /// Per-theme user color overrides, keyed by theme ID.
        case terminalThemeOverrides

        /// Whether OSC 9 attention notifications also post to
        /// Notification Center.
        case attentionNotificationsEnabled

        /// Whether attention notifications play a sound.
        case attentionNotificationSoundEnabled

        /// Whether pasting text with newlines asks for confirmation.
        case confirmMultilinePaste

        /// User-imported terminal themes (e.g. from iTerm2 files).
        case customTerminalThemes

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

    /// Whether the Option key acts as Meta (ESC prefix). Off by default so
    /// international layouts can type characters like @ and ~ (e.g. ⌥2 on
    /// a Swedish keyboard).
    public var optionAsMetaKey: Bool {
        didSet {
            store.save(optionAsMetaKey, for: .optionAsMetaKey)
        }
    }

    /// Terminal scrollback buffer size in lines.
    public var terminalScrollbackLines: Int {
        didSet {
            store.save(terminalScrollbackLines, for: .terminalScrollbackLines)
        }
    }

    /// Terminal tab stop width in columns.
    public var terminalTabStopWidth: Int {
        didSet {
            store.save(terminalTabStopWidth, for: .terminalTabStopWidth)
        }
    }

    /// Terminal cursor shape: "block", "underline", or "bar".
    public var terminalCursorShape: String {
        didSet {
            store.save(terminalCursorShape, for: .terminalCursorShape)
        }
    }

    /// Whether the terminal cursor blinks.
    public var terminalCursorBlinks: Bool {
        didSet {
            store.save(terminalCursorBlinks, for: .terminalCursorBlinks)
        }
    }

    /// Per-theme user color overrides, keyed by theme ID.
    var terminalThemeOverrides: [String: TerminalThemeOverride] {
        didSet {
            store.save(terminalThemeOverrides, for: .terminalThemeOverrides)
        }
    }

    /// Whether OSC 9 attention notifications also post to
    /// Notification Center.
    public var attentionNotificationsEnabled: Bool {
        didSet {
            store.save(attentionNotificationsEnabled, for: .attentionNotificationsEnabled)
        }
    }

    /// Whether attention notifications play a sound.
    public var attentionNotificationSoundEnabled: Bool {
        didSet {
            store.save(attentionNotificationSoundEnabled, for: .attentionNotificationSoundEnabled)
        }
    }

    /// Whether pasting text with newlines asks for confirmation first
    /// (the shell may execute each line immediately).
    public var confirmMultilinePaste: Bool {
        didSet {
            store.save(confirmMultilinePaste, for: .confirmMultilinePaste)
        }
    }

    /// User-imported terminal themes (e.g. from iTerm2 .itermcolors files).
    var customTerminalThemes: [TerminalTheme] {
        didSet {
            store.save(customTerminalThemes, for: .customTerminalThemes)
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
        optionAsMetaKey = self.store.load(.optionAsMetaKey, default: false)
        terminalScrollbackLines = self.store.load(.terminalScrollbackLines, default: 10_000)
        terminalTabStopWidth = self.store.load(.terminalTabStopWidth, default: 8)
        terminalCursorShape = self.store.load(.terminalCursorShape, default: "block")
        terminalCursorBlinks = self.store.load(.terminalCursorBlinks, default: true)
        terminalThemeOverrides = self.store.load(.terminalThemeOverrides, default: [:])
        attentionNotificationsEnabled = self.store.load(.attentionNotificationsEnabled, default: false)
        attentionNotificationSoundEnabled = self.store.load(.attentionNotificationSoundEnabled, default: true)

        confirmMultilinePaste = self.store.load(.confirmMultilinePaste, default: true)
        customTerminalThemes = self.store.load(.customTerminalThemes, default: [])

        // <-- (3 / 3) Add initializer for new property here.
    }
}
