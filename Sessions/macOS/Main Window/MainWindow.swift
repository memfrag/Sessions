//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import SwiftUIToolbox
import Sparkle

struct MainWindow: Scene {

    let updater: SPUUpdater

    @State private var workspacesModel = WorkspacesModel(serverManager: ServerManager())

    var body: some Scene {

        WindowGroup {
            Sidebar()
                .frame(minWidth: 600, minHeight: 400)
                .background(AlwaysOnTop())
                .appEnvironment(.default)
                .environment(workspacesModel)
                #if os(macOS)
                .terminatesAppWhenClosed()
                #endif
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
