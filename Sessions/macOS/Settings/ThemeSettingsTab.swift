//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

/// Theme selection plus per-theme color overrides. Overrides are stored
/// by theme ID, so tweaks to one theme never affect another.
struct ThemeSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    private static let ansiNames = [
        "Black", "Red", "Green", "Yellow", "Blue", "Magenta", "Cyan", "White",
        "Bright Black", "Bright Red", "Bright Green", "Bright Yellow",
        "Bright Blue", "Bright Magenta", "Bright Cyan", "Bright White"
    ]

    /// The selected theme with overrides applied (what the pickers show).
    private var effectiveTheme: TerminalTheme {
        TerminalTheme.theme(withID: settings.terminalThemeID)
            .applying(settings.terminalThemeOverrides[settings.terminalThemeID])
    }

    private var hasOverrides: Bool {
        !(settings.terminalThemeOverrides[settings.terminalThemeID]?.isEmpty ?? true)
    }

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                Picker("Theme:", selection: $settings.terminalThemeID) {
                    ForEach(TerminalTheme.presets) { theme in
                        HStack(spacing: 6) {
                            HStack(spacing: 2) {
                                ForEach(theme.swatchColors, id: \.self) { hex in
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(Color(nsColor: NSColor(hexString: hex) ?? .textBackgroundColor))
                                        .frame(width: 10, height: 10)
                                }
                            }
                            Text(theme.name)
                        }
                        .tag(theme.id)
                    }
                }
            }
            Section("Colors") {
                ColorPicker("Foreground:", selection: binding(\.foreground, base: effectiveTheme.foreground))
                ColorPicker("Background:", selection: binding(\.background, base: effectiveTheme.background))
                ColorPicker("Cursor:", selection: binding(\.cursor, base: effectiveTheme.cursor))
                ColorPicker("Selection:", selection: binding(\.selection, base: effectiveTheme.selection))
            }
            Section("ANSI Colors") {
                ansiGrid
            }
            Section {
                Button("Reset to Theme Colors") {
                    settings.terminalThemeOverrides[settings.terminalThemeID] = nil
                }
                .disabled(!hasOverrides)
            }
        }
        .padding(20)
    }

    private var ansiGrid: some View {
        let ansi = effectiveTheme.ansi.isEmpty ? TerminalTheme.xterm16 : effectiveTheme.ansi
        return VStack(alignment: .leading, spacing: 6) {
            ForEach([0, 8], id: \.self) { rowStart in
                HStack(spacing: 6) {
                    ForEach(rowStart..<(rowStart + 8), id: \.self) { slot in
                        ColorPicker(
                            Self.ansiNames[slot],
                            selection: ansiBinding(slot: slot, base: ansi[slot])
                        )
                        .labelsHidden()
                        .help(Self.ansiNames[slot])
                    }
                }
            }
        }
    }

    // MARK: - Override bindings

    /// A Color binding whose getter shows the effective color and whose
    /// setter writes an override for the selected theme.
    private func binding(
        _ keyPath: WritableKeyPath<TerminalThemeOverride, String?>,
        base: String
    ) -> Binding<Color> {
        Binding {
            Color(nsColor: NSColor(hexString: base) ?? fallbackColor(for: keyPath))
        } set: { newColor in
            var override = settings.terminalThemeOverrides[settings.terminalThemeID] ?? TerminalThemeOverride()
            override[keyPath: keyPath] = NSColor(newColor).hexString
            settings.terminalThemeOverrides[settings.terminalThemeID] = override
        }
    }

    private func ansiBinding(slot: Int, base: String) -> Binding<Color> {
        Binding {
            Color(nsColor: NSColor(hexString: base) ?? .textColor)
        } set: { newColor in
            var override = settings.terminalThemeOverrides[settings.terminalThemeID] ?? TerminalThemeOverride()
            override.ansi[slot] = NSColor(newColor).hexString
            settings.terminalThemeOverrides[settings.terminalThemeID] = override
        }
    }

    /// The system theme has empty base hex strings; show its native colors.
    private func fallbackColor(for keyPath: WritableKeyPath<TerminalThemeOverride, String?>) -> NSColor {
        switch keyPath {
        case \.background: .textBackgroundColor
        case \.selection: .selectedTextBackgroundColor
        default: .textColor
        }
    }
}

#Preview {
    ThemeSettingsTab()
        .previewEnvironment()
}
