//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit

/// A terminal color theme: 16 ANSI colors plus default foreground,
/// background, cursor, and selection colors, all as "#RRGGBB" hex strings.
///
/// The special `system` theme follows the macOS appearance via
/// `configureNativeColors()` instead of fixed colors.
struct TerminalTheme: Identifiable, Hashable, Codable {

    static let systemThemeID = "system"

    let id: String

    let name: String

    /// Exactly 16 ANSI colors (normal 0-7, bright 8-15). Empty for the
    /// system theme, which uses the standard xterm palette.
    let ansi: [String]

    let foreground: String

    let background: String

    let cursor: String

    let selection: String

    var isSystem: Bool { id == Self.systemThemeID }

    /// The effective terminal background color (the system theme uses the
    /// native text-background color).
    var effectiveBackgroundColor: NSColor {
        NSColor(hexString: background) ?? .textBackgroundColor
    }

    /// The standard xterm 16-color palette, used by the system theme.
    static let xterm16 = [
        "#000000", "#cd0000", "#00cd00", "#cdcd00",
        "#0000ee", "#cd00cd", "#00cdcd", "#e5e5e5",
        "#7f7f7f", "#ff0000", "#00ff00", "#ffff00",
        "#5c5cff", "#ff00ff", "#00ffff", "#ffffff"
    ]
}

// MARK: - Hex parsing

extension NSColor {

    /// Parses "#RRGGBB" (leading "#" optional).
    convenience init?(hexString: String) {
        guard let (red, green, blue) = parseHexRGB(hexString) else { return nil }
        self.init(
            srgbRed: CGFloat(red) / 255,
            green: CGFloat(green) / 255,
            blue: CGFloat(blue) / 255,
            alpha: 1
        )
    }
}

/// Parses "#RRGGBB" (leading "#" optional) into 8-bit RGB. Shared by the
/// `NSColor` and engine color parsers.
func parseHexRGB(_ hexString: String) -> (UInt8, UInt8, UInt8)? {
    var hex = hexString
    if hex.hasPrefix("#") {
        hex.removeFirst()
    }
    guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
    return (
        UInt8((value >> 16) & 0xFF),
        UInt8((value >> 8) & 0xFF),
        UInt8(value & 0xFF)
    )
}
