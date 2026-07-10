//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Toolbar menu listing snippet names for quick pasting, with "Manage
/// Snippets…" to open the snippets window.
struct SnippetsToolbarMenu: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(AppSettings.self) private var settings

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Menu {
            Button("Manage Snippets…") {
                openWindow(id: SnippetsWindow.windowID)
            }
            if settings.snippets.isEmpty {
                Divider()
                Text("No Snippets")
            } else {
                Divider()
                ForEach(settings.snippets) { snippet in
                    Button(snippet.title.isEmpty ? "Untitled Snippet" : snippet.title) {
                        model.useSnippet(snippet)
                    }
                }
            }
        } label: {
            Label("Snippets", systemImage: "text.append")
        }
        .help("Paste a snippet into the active terminal")
    }
}
