//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation

/// One runnable entry in the command palette.
struct PaletteCommand: Identifiable {

    let id: String

    let title: String

    /// Secondary line shown under the title (e.g. "Switch to Workspace").
    let subtitle: String?

    let systemImage: String

    /// Display-only hint like "⌘T" for commands that also have a menu shortcut.
    let shortcutHint: String?

    let action: @MainActor () -> Void

    init(
        id: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        shortcutHint: String? = nil,
        action: @escaping @MainActor () -> Void
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.systemImage = systemImage
        self.shortcutHint = shortcutHint
        self.action = action
    }
}
