//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Menu bar status item: server health and live sessions at a glance.
/// The app keeps running with the last window closed; this is the way
/// back in.
struct SessionsMenuBar: Scene {

    let workspacesModel: WorkspacesModel

    var body: some Scene {
        MenuBarExtra {
            SessionsMenuBarView()
                .environment(workspacesModel)
        } label: {
            Image(
                systemName: workspacesModel.anyWorkspaceNeedsAttention
                    ? "bell.badge.fill"
                    : "terminal"
            )
        }
        .menuBarExtraStyle(.window)
    }
}
