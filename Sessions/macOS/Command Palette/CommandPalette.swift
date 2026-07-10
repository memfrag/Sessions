//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

// MARK: - Command model

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

// MARK: - Overlay

/// Full-window overlay hosting the palette: dimmed click-to-dismiss
/// backdrop with the panel near the top, Spotlight-style.
struct CommandPaletteOverlay: View {

    @Environment(WorkspacesModel.self) private var model

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.15)
                .ignoresSafeArea()
                .onTapGesture {
                    model.isCommandPaletteVisible = false
                }
            CommandPaletteView()
                .padding(.top, 48)
        }
    }
}

// MARK: - Palette panel

/// The palette itself: query field on top, fuzzy-filtered command list
/// below. ↑/↓ move the selection, Return runs it, Esc dismisses.
struct CommandPaletteView: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(AppSettings.self) private var settings

    @Environment(\.openSettings) private var openSettings

    @State private var query = ""

    @State private var selectedIndex = 0

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        let results = filteredCommands
        VStack(spacing: 0) {
            queryField
            Divider()
            if results.isEmpty {
                Text("No matching commands")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                resultsList(results)
            }
        }
        .frame(width: 520)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(radius: 16, y: 4)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .onExitCommand {
            dismiss()
        }
        .defaultFocus($isFieldFocused, true)
        .onAppear {
            // Deferred one runloop turn: setting FocusState synchronously
            // during overlay insertion fails silently (the field is not in
            // the responder chain yet) and typing keeps going to the
            // terminal underneath.
            isFieldFocused = true
            DispatchQueue.main.async {
                isFieldFocused = true
            }
        }
        .onChange(of: query) {
            selectedIndex = 0
        }
    }

    private var queryField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("Type a command…", text: $query)
                .textFieldStyle(.plain)
                .font(.title3)
                .focused($isFieldFocused)
                .onSubmit {
                    runSelectedCommand()
                }
                // Arrow keys arrive as move commands from the field
                // editor (moveUp:/moveDown:), not as raw key presses —
                // and `onKeyPress` handlers can double-fire alongside
                // them, so this is the single source of selection moves.
                .onMoveCommand { direction in
                    switch direction {
                    case .up: moveSelection(-1)
                    case .down: moveSelection(1)
                    default: break
                    }
                }
        }
        .padding(12)
    }

    private func resultsList(_ results: [PaletteCommand]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                // A plain VStack, and row identity is the command id alone:
                // a second positional `.id(index)` made the lazy stack
                // recycle stale row content when the results changed.
                VStack(spacing: 2) {
                    ForEach(Array(results.enumerated()), id: \.element.id) { index, command in
                        // Hover deliberately does NOT move the keyboard
                        // selection: auto-scroll shifts rows under a
                        // stationary pointer, and hover-selection would
                        // feed back into more scrolling.
                        CommandPaletteRow(
                            command: command,
                            isSelected: index == selectedIndex
                        )
                        .onTapGesture {
                            run(command)
                        }
                    }
                }
                .padding(6)
            }
            .frame(maxHeight: 320)
            .onChange(of: selectedIndex) {
                if results.indices.contains(selectedIndex) {
                    proxy.scrollTo(results[selectedIndex].id)
                }
            }
        }
    }

    // MARK: Selection and execution

    private func moveSelection(_ offset: Int) {
        let count = filteredCommands.count
        guard count > 0 else { return }
        selectedIndex = (selectedIndex + offset + count) % count
    }

    private func runSelectedCommand() {
        let results = filteredCommands
        guard results.indices.contains(selectedIndex) else { return }
        run(results[selectedIndex])
    }

    private func run(_ command: PaletteCommand) {
        dismiss()
        command.action()
    }

    private func dismiss() {
        model.isCommandPaletteVisible = false
    }

    // MARK: Command catalog

    private var filteredCommands: [PaletteCommand] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let commands = allCommands
        if trimmed.isEmpty {
            return commands
        }
        return commands
            .compactMap { command -> (command: PaletteCommand, score: Int)? in
                let titleScore = FuzzyMatch.score(query: trimmed, in: command.title)
                // Subtitles match too ("dracula" under "Theme"), discounted
                // so title matches always rank first.
                let subtitleScore = command.subtitle
                    .flatMap { FuzzyMatch.score(query: trimmed, in: $0) }
                    .map { $0 - 10 }
                guard let score = [titleScore, subtitleScore].compactMap({ $0 }).max() else {
                    return nil
                }
                return (command, score)
            }
            .sorted { $0.score > $1.score }
            .map(\.command)
    }

    private var allCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = []
        commands.append(contentsOf: actionCommands)
        commands.append(contentsOf: workspaceCommands)
        commands.append(contentsOf: tabCommands)
        commands.append(contentsOf: themeCommands)
        return commands
    }

    private var actionCommands: [PaletteCommand] {
        var commands: [PaletteCommand] = []
        if model.selectedWorkspace != nil {
            commands.append(PaletteCommand(
                id: "action-new-tab",
                title: "New Tab",
                systemImage: "plus.rectangle",
                shortcutHint: "⌘T"
            ) { [model] in
                model.newTabInSelectedWorkspace()
            })
        }
        if !(model.selectedWorkspace?.sessions.isEmpty ?? true) {
            commands.append(PaletteCommand(
                id: "action-close-tab",
                title: "Close Tab",
                systemImage: "xmark.rectangle",
                shortcutHint: "⌘W"
            ) { [model] in
                model.closeSelectedTab()
            })
        }
        commands.append(PaletteCommand(
            id: "action-new-workspace",
            title: "New Workspace…",
            systemImage: "folder.badge.plus",
            shortcutHint: "⇧⌘N"
        ) { [model] in
            model.isNewWorkspaceSheetPresented = true
        })
        if model.selectedTerminalController != nil {
            commands.append(PaletteCommand(
                id: "action-find",
                title: "Find in Terminal",
                systemImage: "magnifyingglass",
                shortcutHint: "⌘F"
            ) { [model] in
                model.selectedTerminalController?.showFindBar()
            })
        }
        // Current working directory of the focused tab (via OSC 7);
        // absent without shell integration.
        if let directory = model.selectedTerminalController?.currentDirectory {
            commands.append(PaletteCommand(
                id: "action-open-in-finder",
                title: "Open Current Directory in Finder",
                subtitle: (directory as NSString).abbreviatingWithTildeInPath,
                systemImage: "folder.circle"
            ) {
                NSWorkspace.shared.open(URL(filePath: directory, directoryHint: .isDirectory))
            })
        }
        if (model.selectedWorkspace?.sessions.count ?? 0) > 1 {
            commands.append(PaletteCommand(
                id: "action-next-tab",
                title: "Next Tab",
                systemImage: "arrow.forward.square",
                shortcutHint: "⇧⌘]"
            ) { [model] in
                model.selectAdjacentTab(offset: 1)
            })
            commands.append(PaletteCommand(
                id: "action-previous-tab",
                title: "Previous Tab",
                systemImage: "arrow.backward.square",
                shortcutHint: "⇧⌘["
            ) { [model] in
                model.selectAdjacentTab(offset: -1)
            })
        }
        commands.append(PaletteCommand(
            id: "action-settings",
            title: "Settings…",
            systemImage: "gearshape",
            shortcutHint: "⌘,"
        ) { [openSettings] in
            openSettings()
        })
        commands.append(PaletteCommand(
            id: "action-restart-server",
            title: "Restart Session Server",
            subtitle: "Terminates all shells; workspaces and tabs are kept",
            systemImage: "arrow.clockwise.circle"
        ) { [model] in
            model.serverManager.restartServer()
        })
        commands.append(PaletteCommand(
            id: "action-quit-stop-all",
            title: "Quit and Stop All Sessions",
            systemImage: "power",
            shortcutHint: "⌥⌘Q"
        ) { [model] in
            model.serverManager.closeAllSessionsAndQuit()
        })
        return commands
    }

    private var workspaceCommands: [PaletteCommand] {
        model.workspaces.map { workspace in
            let isCurrent = workspace.id == model.selectedWorkspaceID
            return PaletteCommand(
                id: "workspace-\(workspace.id)",
                title: workspace.name,
                subtitle: "Switch to Workspace",
                systemImage: "folder",
                shortcutHint: isCurrent ? "Current" : nil
            ) { [model] in
                model.selectedWorkspaceID = workspace.id
            }
        }
    }

    private var tabCommands: [PaletteCommand] {
        model.workspaces.flatMap { workspace in
            workspace.sessions.map { session in
                PaletteCommand(
                    id: "tab-\(session.id)",
                    title: model.sessionTitle(for: session),
                    subtitle: "Go to Tab — \(workspace.name)",
                    systemImage: "terminal"
                ) { [model] in
                    model.selectedWorkspaceID = workspace.id
                    model.selectSession(id: session.id, in: workspace.id)
                }
            }
        }
    }

    private var themeCommands: [PaletteCommand] {
        TerminalTheme.presets.map { theme in
            let isCurrent = theme.id == settings.terminalThemeID
            return PaletteCommand(
                id: "theme-\(theme.id)",
                title: "Theme: \(theme.name)",
                subtitle: "Appearance",
                systemImage: isCurrent ? "checkmark.circle.fill" : "paintpalette",
                shortcutHint: isCurrent ? "Current" : nil
            ) { [settings] in
                settings.terminalThemeID = theme.id
            }
        }
    }
}

// MARK: - Row

private struct CommandPaletteRow: View {

    let command: PaletteCommand

    let isSelected: Bool

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: command.systemImage)
                .frame(width: 20)
                .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            VStack(alignment: .leading, spacing: 1) {
                Text(command.title)
                    .lineLimit(1)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
                if let subtitle = command.subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
                }
            }
            Spacer()
            if let hint = command.shortcutHint {
                Text(hint)
                    .font(.callout)
                    .foregroundStyle(isSelected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.accentColor : Color.clear)
        )
        .contentShape(Rectangle())
    }
}
