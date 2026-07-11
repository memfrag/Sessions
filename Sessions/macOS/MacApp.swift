//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import AttributionsUI
import AppDesign
import Sparkle

@main
struct MacApp: App {
    
    // swiftlint:disable:next weak_delegate
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    
    private let updaterController = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: nil,
        userDriverDelegate: nil
    )
    
    @State private var workspacesModel = WorkspacesModel(serverManager: ServerManager())

    init() {
        AppDesign.apply()
    }

    var body: some Scene {
        MainWindow(updater: updaterController.updater, workspacesModel: workspacesModel)
        SessionsMenuBar(workspacesModel: workspacesModel)
        SettingsWindow()
        AboutWindow(developedBy: "Apparata AB",
                    attributionsWindowID: AttributionsWindow.windowID)
        AttributionsWindow([
            ("CGMath", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("MathKit", .bsd0Clause(year: "2025", holder: "Apparata AB")),
            ("Sparkle", .mit(year: "2006-2017", holder: "Andy Matuschak et al.")),
            ("Ghostty", .mit(year: "2024", holder: "Mitchell Hashimoto")),
            ("libghostty-spm", .mit(year: "2026", holder: "Lakr233")),
            ("MSDisplayLink", .mit(year: "2024", holder: "Lakr Aream"))
        ], header: "The following software may be included in this product.")
        HelpWindow()
        SnippetsWindow(workspacesModel: workspacesModel)
    }
}
