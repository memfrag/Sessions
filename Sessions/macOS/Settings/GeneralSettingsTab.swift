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
                    HStack {
                        Slider(value: $settings.terminalFontSize, in: 9...24, step: 1) {
                            EmptyView()
                        }
                        .frame(width: 180)
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
