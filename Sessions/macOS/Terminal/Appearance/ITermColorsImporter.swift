//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

enum ITermColorsImportError: LocalizedError {
    case notAPlist
    case missingColors

    var errorDescription: String? {
        switch self {
        case .notAPlist:
            "The file is not a valid .itermcolors property list."
        case .missingColors:
            "The file is missing required colors (16 ANSI colors, foreground, and background)."
        }
    }
}

/// Imports iTerm2 `.itermcolors` files as custom terminal themes.
///
/// The format is an XML plist mapping names like "Ansi 0 Color" and
/// "Foreground Color" to dictionaries of "Red/Green/Blue Component"
/// doubles in 0...1 (alpha and color space are ignored; sRGB assumed).
enum ITermColorsImporter {

    static func importTheme(data: Data, name: String) throws -> TerminalTheme {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil),
              let dictionary = plist as? [String: Any] else {
            throw ITermColorsImportError.notAPlist
        }
        let ansi = (0..<16).compactMap { index in
            hexColor(dictionary["Ansi \(index) Color"])
        }
        guard ansi.count == 16,
              let foreground = hexColor(dictionary["Foreground Color"]),
              let background = hexColor(dictionary["Background Color"]) else {
            throw ITermColorsImportError.missingColors
        }
        return TerminalTheme(
            id: "custom-\(UUID().uuidString)",
            name: name,
            ansi: ansi,
            foreground: foreground,
            background: background,
            cursor: hexColor(dictionary["Cursor Color"]) ?? foreground,
            selection: hexColor(dictionary["Selection Color"]) ?? background
        )
    }

    /// One color entry ("Red Component" etc., 0...1 doubles) as "#RRGGBB".
    private static func hexColor(_ entry: Any?) -> String? {
        guard let components = entry as? [String: Any],
              let red = components["Red Component"] as? Double,
              let green = components["Green Component"] as? Double,
              let blue = components["Blue Component"] as? Double else {
            return nil
        }
        func channel(_ value: Double) -> Int {
            Int((min(max(value, 0), 1) * 255).rounded())
        }
        return String(format: "#%02x%02x%02x", channel(red), channel(green), channel(blue))
    }
}
