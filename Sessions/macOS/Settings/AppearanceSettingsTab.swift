//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

struct AppearanceSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    /// Fixed-pitch font families, computed once (enumeration is not fast).
    @State private var monospacedFamilies: [String] = []

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Theme") {
                Picker("Theme:", selection: $settings.terminalThemeID) {
                    ForEach(TerminalTheme.presets) { theme in
                        HStack(spacing: 6) {
                            // Plain shape fills only: no Slider, no materials
                            // (RenderBox crash constraint on macOS 26.4).
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
            Section("Font") {
                Picker("Font:", selection: $settings.terminalFontName) {
                    Text("SF Mono (System)").tag("")
                    ForEach(monospacedFamilies, id: \.self) { family in
                        Text(family).tag(family)
                    }
                }
                LabeledContent("Size:") {
                    Stepper(value: $settings.terminalFontSize, in: 9...24, step: 1) {
                        Text("\(Int(settings.terminalFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
            Section("Rendering") {
                Toggle("Use Metal renderer (experimental)", isOn: $settings.useMetalRenderer)
                Text("GPU-accelerated rendering. Turn off if you see drawing glitches.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
        .task {
            monospacedFamilies = Self.findMonospacedFamilies()
        }
    }

    private static func findMonospacedFamilies() -> [String] {
        let manager = NSFontManager.shared
        return manager.availableFontFamilies.filter { family in
            guard !family.hasPrefix(".") else { return false }
            guard let font = manager.font(withFamily: family, traits: [], weight: 5, size: 12) else {
                return false
            }
            return font.isFixedPitch
        }
    }
}

#Preview {
    AppearanceSettingsTab()
        .previewEnvironment()
}
