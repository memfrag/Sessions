//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    static let windowID = "main"

    let updater: SPUUpdater

    let workspacesModel: WorkspacesModel

    var body: some Scene {

        // A single-instance Window (not a WindowGroup) so there is only
        // ever one main window; openWindow(id:) then brings the existing
        // window forward instead of spawning a new one.
        Window("Sessions", id: Self.windowID) {
            Sidebar()
                .frame(minWidth: 600, minHeight: 400)
                .background(AlwaysOnTop())
                .appEnvironment(.default)
                .environment(workspacesModel)
        }
        .commands {
            AboutCommand()
            CheckForUpdatesCommand(updater: updater)
            SidebarCommands()
            AlwaysOnTopCommand()
            HelpCommands()
            TerminalCommands()
        }
    }
}
