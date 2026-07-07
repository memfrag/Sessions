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

        WindowGroup(id: Self.windowID) {
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
