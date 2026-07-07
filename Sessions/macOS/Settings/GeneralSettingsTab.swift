//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

struct GeneralSettingsTab: View {

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Terminal") {
                LabeledContent("Font Size:") {
                    // Deliberately a Stepper, not a Slider: SwiftUI Slider
                    // triggers a RenderBox default.metallib crash on
                    // macOS 26.4 (FB/forums thread 799874).
                    Stepper(value: $settings.terminalFontSize, in: 9...24, step: 1) {
                        Text("\(Int(settings.terminalFontSize)) pt")
                            .monospacedDigit()
                            .frame(width: 44, alignment: .trailing)
                    }
                }
            }
        }
        .padding(20)
    }
}

#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
