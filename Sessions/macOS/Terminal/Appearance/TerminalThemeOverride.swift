//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// User color overrides applied on top of a theme preset, stored per
/// theme ID so tweaks to one theme do not leak into another. All values
/// are "#RRGGBB" hex strings; nil/absent means "use the theme's color".
struct TerminalThemeOverride: Codable, Hashable {

    var foreground: String?

    var background: String?

    var cursor: String?

    var selection: String?

    /// ANSI slot (0-15) → hex override.
    var ansi: [Int: String] = [:]

    var isEmpty: Bool {
        foreground == nil && background == nil && cursor == nil
            && selection == nil && ansi.isEmpty
    }
}

extension TerminalTheme {

    /// The theme with user overrides applied. The system theme gets the
    /// concrete xterm palette as its base so ANSI slots can be overridden.
    func applying(_ override: TerminalThemeOverride?) -> TerminalTheme {
        guard let override, !override.isEmpty else { return self }
        var ansiColors = ansi.isEmpty ? Self.xterm16 : ansi
        for (slot, hex) in override.ansi where ansiColors.indices.contains(slot) {
            ansiColors[slot] = hex
        }
        return TerminalTheme(
            id: id,
            name: name,
            ansi: ansiColors,
            foreground: override.foreground ?? foreground,
            background: override.background ?? background,
            cursor: override.cursor ?? cursor,
            selection: override.selection ?? selection
        )
    }
}

extension NSColor {

    /// "#RRGGBB" in sRGB, for storing picker choices.
    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        let red = Int(round(color.redComponent * 255))
        let green = Int(round(color.greenComponent * 255))
        let blue = Int(round(color.blueComponent * 255))
        return String(format: "#%02x%02x%02x", red, green, blue)
    }
}
