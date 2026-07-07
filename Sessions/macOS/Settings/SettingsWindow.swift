//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Show settings window by using a SettingsLink SwiftUI view.
struct SettingsWindow: Scene {

    private enum Tabs: Hashable {
        case general
        case appearance
    }

    var body: some Scene {
        Settings {
            tabs
                .appEnvironment(.default)
        }
    }

    @ViewBuilder var tabs: some View {
        TabView {
            GeneralSettingsTab()
                .tabItem {
                    Label("General", systemImage: "gear")
                }
                .tag(Tabs.general)
            AppearanceSettingsTab()
                .tabItem {
                    Label("Appearance", systemImage: "paintpalette")
                }
                .tag(Tabs.appearance)
        }
        .padding(20)
        .frame(width: 460, height: 340)
    }
}
