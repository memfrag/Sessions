//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

// MARK: - Focused values

extension FocusedValues {
    /// The workspaces model of the focused main window, for menu commands.
    @Entry var workspacesModel: WorkspacesModel?
}

// MARK: - Commands

/// File-menu and Tabs-menu commands for workspaces and terminal tabs.
struct TerminalCommands: Commands {

    @FocusedValue(\.workspacesModel) private var model

    @Environment(\.openWindow) private var openWindow

    var body: some Commands {

        CommandGroup(replacing: .newItem) {
            Button("New Workspace…") {
                model?.beginNewWorkspace()
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            .disabled(model == nil)

            Button("New Tab") {
                model?.newTabInSelectedWorkspace()
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(model?.selectedWorkspace == nil)
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close Tab") {
                model?.closeSelectedTab()
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(model?.selectedWorkspace?.sessions.isEmpty ?? true)

            Button("Close Window") {
                NSApplication.shared.keyWindow?.performClose(nil)
            }
            .keyboardShortcut("w", modifiers: [.command, .shift])
        }

        CommandGroup(after: .sidebar) {
            Button("Command Palette…") {
                model?.isCommandPaletteVisible.toggle()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(model == nil)

            Button("Snippets…") {
                openWindow(id: SnippetsWindow.windowID)
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])

            #if DEBUG
            Button("Ghostty Spike…") {
                openWindow(id: GhosttySpikeWindow.windowID)
            }
            #endif
        }

        CommandGroup(after: .textEditing) {
            Button("Find…") {
                model?.selectedTerminalController?.showFindBar()
            }
            .keyboardShortcut("f", modifiers: .command)
            .disabled(model?.selectedTerminalController == nil)

            Button("Find Next") {
                model?.selectedTerminalController?.findNext()
            }
            .keyboardShortcut("g", modifiers: .command)
            .disabled(model?.selectedTerminalController == nil)

            Button("Find Previous") {
                model?.selectedTerminalController?.findPrevious()
            }
            .keyboardShortcut("g", modifiers: [.command, .shift])
            .disabled(model?.selectedTerminalController == nil)
        }

        CommandMenu("Tabs") {
            Button("Next Tab") {
                model?.selectAdjacentTab(offset: 1)
            }
            .keyboardShortcut("]", modifiers: [.command, .shift])
            .disabled((model?.selectedWorkspace?.sessions.count ?? 0) < 2)

            Button("Previous Tab") {
                model?.selectAdjacentTab(offset: -1)
            }
            .keyboardShortcut("[", modifiers: [.command, .shift])
            .disabled((model?.selectedWorkspace?.sessions.count ?? 0) < 2)

            Divider()

            ForEach(1...9, id: \.self) { number in
                Button("Tab \(number)") {
                    model?.selectTab(atIndex: number - 1)
                }
                .keyboardShortcut(KeyEquivalent(Character("\(number)")), modifiers: .command)
                .disabled((model?.selectedWorkspace?.sessions.count ?? 0) < number)
            }
        }

        CommandGroup(after: .appTermination) {
            Button("Quit and Stop All Sessions") {
                model?.serverManager.closeAllSessionsAndQuit()
            }
            .keyboardShortcut("q", modifiers: [.command, .option])
            .disabled(model == nil)
        }
    }
}
