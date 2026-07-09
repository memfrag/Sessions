//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

extension TerminalTheme {

    /// Built-in themes, in the order shown in Settings.
    static let presets: [TerminalTheme] = [
        TerminalTheme(
            id: systemThemeID,
            name: "System",
            ansi: [],
            foreground: "",
            background: "",
            cursor: "",
            selection: ""
        ),
        TerminalTheme(
            id: "solarized-dark",
            name: "Solarized Dark",
            ansi: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
            ],
            foreground: "#839496",
            background: "#002b36",
            cursor: "#839496",
            selection: "#073642"
        ),
        TerminalTheme(
            id: "solarized-light",
            name: "Solarized Light",
            ansi: [
                "#073642", "#dc322f", "#859900", "#b58900",
                "#268bd2", "#d33682", "#2aa198", "#eee8d5",
                "#002b36", "#cb4b16", "#586e75", "#657b83",
                "#839496", "#6c71c4", "#93a1a1", "#fdf6e3"
            ],
            foreground: "#657b83",
            background: "#fdf6e3",
            cursor: "#657b83",
            selection: "#eee8d5"
        ),
        TerminalTheme(
            id: "dracula",
            name: "Dracula",
            ansi: [
                "#21222c", "#ff5555", "#50fa7b", "#f1fa8c",
                "#bd93f9", "#ff79c6", "#8be9fd", "#f8f8f2",
                "#6272a4", "#ff6e6e", "#69ff94", "#ffffa5",
                "#d6acff", "#ff92df", "#a4ffff", "#ffffff"
            ],
            foreground: "#f8f8f2",
            background: "#282a36",
            cursor: "#f8f8f2",
            selection: "#44475a"
        ),
        TerminalTheme(
            id: "nord",
            name: "Nord",
            ansi: [
                "#3b4252", "#bf616a", "#a3be8c", "#ebcb8b",
                "#81a1c1", "#b48ead", "#88c0d0", "#e5e9f0",
                "#4c566a", "#bf616a", "#a3be8c", "#ebcb8b",
                "#81a1c1", "#b48ead", "#8fbcbb", "#eceff4"
            ],
            foreground: "#d8dee9",
            background: "#2e3440",
            cursor: "#d8dee9",
            selection: "#434c5e"
        ),
        TerminalTheme(
            // Palette from the iTerm2-Color-Schemes collection (the same
            // source Ghostty bundles).
            id: "vercel",
            name: "Vercel",
            ansi: [
                "#000000", "#fc0036", "#29a948", "#ffae00",
                "#006aff", "#f32882", "#00ac96", "#feffff",
                "#a8a8a8", "#ff8080", "#4be15d", "#ffae00",
                "#49aeff", "#f97ea8", "#00e4c4", "#fefefe"
            ],
            foreground: "#fafafa",
            background: "#101010",
            cursor: "#f32882",
            selection: "#005be7"
        ),
        TerminalTheme(
            id: "one-dark",
            name: "One Dark",
            ansi: [
                "#282c34", "#e06c75", "#98c379", "#e5c07b",
                "#61afef", "#c678dd", "#56b6c2", "#abb2bf",
                "#5c6370", "#e06c75", "#98c379", "#e5c07b",
                "#61afef", "#c678dd", "#56b6c2", "#ffffff"
            ],
            foreground: "#abb2bf",
            background: "#282c34",
            cursor: "#528bff",
            selection: "#3e4451"
        )
    ]

    /// Resolves a theme ID against the presets plus the user's imported
    /// custom themes, falling back to the system theme for unknown IDs
    /// (e.g. a removed preset or a deleted custom theme).
    static func theme(withID id: String, custom: [TerminalTheme] = []) -> TerminalTheme {
        presets.first { $0.id == id }
            ?? custom.first { $0.id == id }
            ?? presets[0]
    }

    /// Representative swatch colors for the settings picker row.
    var swatchColors: [String] {
        if isSystem {
            return Array(Self.xterm16[1..<8])
        }
        var colors = [background]
        colors.append(contentsOf: ansi.prefix(8).dropFirst(1))
        return colors
    }
}
