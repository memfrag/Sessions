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
        Form {
            fontSection
            terminalSection
            inputSection
            renderingSection
        }
        .padding(20)
        .task {
            monospacedFamilies = Self.findMonospacedFamilies()
        }
    }

    private var fontSection: some View {
        @Bindable var settings = settings
        return Section("Font") {
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
    }

    private var terminalSection: some View {
        @Bindable var settings = settings
        return Section("Terminal") {
            Picker("Cursor:", selection: $settings.terminalCursorShape) {
                Text("Block").tag("block")
                Text("Underline").tag("underline")
                Text("Bar").tag("bar")
            }
            .pickerStyle(.segmented)
            Toggle("Blinking cursor", isOn: $settings.terminalCursorBlinks)
            Picker("Scrollback:", selection: $settings.terminalScrollbackLines) {
                Text("1 000 lines").tag(1_000)
                Text("5 000 lines").tag(5_000)
                Text("10 000 lines").tag(10_000)
                Text("50 000 lines").tag(50_000)
                Text("100 000 lines").tag(100_000)
            }
            LabeledContent("Tab Width:") {
                Stepper(value: $settings.terminalTabStopWidth, in: 1...16, step: 1) {
                    Text("\(settings.terminalTabStopWidth) columns")
                        .monospacedDigit()
                        .frame(width: 84, alignment: .trailing)
                }
            }
        }
    }

    private var inputSection: some View {
        @Bindable var settings = settings
        return Section("Input") {
            Toggle("Use Option key as Meta", isOn: $settings.optionAsMetaKey)
            Text("""
            Sends ⌥-key combinations as ESC sequences (for Emacs-style \
            shortcuts). Leave off to type characters like @ and ~ on \
            international keyboard layouts.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            Toggle("Confirm before pasting multiple lines", isOn: $settings.confirmMultilinePaste)
            Text("""
            Pasted text that contains newlines may be executed by the \
            shell immediately; asking first prevents accidents.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private var renderingSection: some View {
        @Bindable var settings = settings
        return Section("Rendering") {
            Toggle("Use Metal renderer (experimental)", isOn: $settings.useMetalRenderer)
            Text("GPU-accelerated rendering. Turn off if you see drawing glitches.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

#if DEBUG
#Preview {
    AppearanceSettingsTab()
        .previewEnvironment()
}
#endif
