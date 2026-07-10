//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Window for browsing, editing, and pasting reusable text snippets.
/// A `Window(id:)` does not inherit the app's model, so the shared
/// `WorkspacesModel` is passed in explicitly (like `MainWindow`).
struct SnippetsWindow: Scene {

    static let windowID = "snippets"

    let workspacesModel: WorkspacesModel

    var body: some Scene {
        Window("Snippets", id: Self.windowID) {
            SnippetsWindowView()
                .frame(minWidth: 560, minHeight: 360)
                .appEnvironment(.default)
                .environment(workspacesModel)
        }
        .commandsRemoved()
        .defaultPosition(.center)
        .defaultSize(width: 720, height: 460)
    }
}
