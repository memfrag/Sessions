//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftTerm

/// A terminal color theme: 16 ANSI colors plus default foreground,
/// background, cursor, and selection colors, all as "#RRGGBB" hex strings.
///
/// The special `system` theme follows the macOS appearance via
/// `configureNativeColors()` instead of fixed colors.
struct TerminalTheme: Identifiable, Hashable {

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

    /// Applies the theme to a terminal view and syncs the margin
    /// container's background to the terminal background.
    @MainActor
    func apply(to terminalView: TerminalView, container: TerminalContainerView?) {
        if isSystem {
            terminalView.configureNativeColors()
            terminalView.installColors(Self.swiftTermColors(from: Self.xterm16))
            terminalView.caretColor = .textColor
            terminalView.caretTextColor = nil
            terminalView.selectedTextBackgroundColor = .selectedTextBackgroundColor
        } else {
            let colors = Self.swiftTermColors(from: ansi)
            if colors.count == 16 {
                terminalView.installColors(colors)
            }
            if let color = NSColor(hexString: foreground) {
                terminalView.nativeForegroundColor = color
            }
            if let color = NSColor(hexString: background) {
                terminalView.nativeBackgroundColor = color
            }
            if let color = NSColor(hexString: cursor) {
                terminalView.caretColor = color
            }
            terminalView.caretTextColor = NSColor(hexString: background)
            if let color = NSColor(hexString: selection) {
                terminalView.selectedTextBackgroundColor = color
            }
        }
        container?.backgroundColor = terminalView.nativeBackgroundColor
    }

    private static func swiftTermColors(from hexStrings: [String]) -> [SwiftTerm.Color] {
        hexStrings.compactMap { SwiftTerm.Color(hexString: $0) }
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

extension SwiftTerm.Color {

    /// Parses "#RRGGBB" into SwiftTerm's 16-bit-per-channel color.
    convenience init?(hexString: String) {
        guard let (red, green, blue) = parseHexRGB(hexString) else { return nil }
        self.init(
            red: UInt16(red) * 257,
            green: UInt16(green) * 257,
            blue: UInt16(blue) * 257
        )
    }
}

private func parseHexRGB(_ hexString: String) -> (UInt8, UInt8, UInt8)? {
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
