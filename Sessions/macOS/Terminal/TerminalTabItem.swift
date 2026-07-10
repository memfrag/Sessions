//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SessionsProtocol
import SwiftUI

/// One tab in the tab strip: title, dead/bell badges, close-on-hover,
/// double-click to rename.
struct TerminalTabItem: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    let session: SessionInfo

    let isSelected: Bool

    let terminalBackground: Color

    @State private var isHovering = false

    @State private var isRenaming = false

    @State private var renameText = ""

    @FocusState private var isRenameFieldFocused: Bool

    private var controller: TerminalSessionController {
        model.sessionRegistry.controller(for: session.id)
    }

    private var title: String {
        model.sessionTitle(for: session)
    }

    private var directoryTooltip: String? {
        guard let directory = controller.currentDirectory else { return nil }
        return (directory as NSString).abbreviatingWithTildeInPath
    }

    private var hasExited: Bool {
        !session.isAlive && session.exitCode != nil
    }

    var body: some View {
        HStack(spacing: 6) {
            leadingIcon
                .font(.system(size: 13))
                .frame(width: 16)
            label
            Spacer(minLength: 0)
            closeButton
        }
        .font(.callout)
        .foregroundStyle(isSelected ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
        .padding(.horizontal, 12)
        .frame(maxHeight: .infinity)
        .frame(minWidth: 90, idealWidth: 160, maxWidth: 220)
        .background(tabBackground)
        .overlay(alignment: .top) { accentStripe }
        .overlay(alignment: .trailing) { separator }
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovering = hovering
        }
        .gesture(
            TapGesture(count: 2).onEnded {
                beginRename()
            }
        )
        .simultaneousGesture(
            TapGesture(count: 1).onEnded {
                model.selectSession(id: session.id, in: workspace.id)
            }
        )
        .contextMenu {
            Button("Rename…") {
                beginRename()
            }
            Button("Reveal in Finder") {
                // The tab's cwd (via OSC 7) when known, else the
                // workspace root.
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath: controller.currentDirectory ?? workspace.rootPath
                )
            }
            Button("Clear Scrollback") {
                controller.clearScrollback()
            }
            Divider()
            Button("Close Tab") {
                model.requestCloseSession(id: session.id)
            }
        }
        .draggable(session.id.uuidString)
        .dropDestination(for: String.self) { items, _ in
            guard let draggedID = items.first.flatMap(UUID.init),
                  draggedID != session.id,
                  let targetIndex = workspace.sessions.firstIndex(where: { $0.id == session.id })
            else {
                return false
            }
            model.moveSession(id: draggedID, toIndex: targetIndex)
            return true
        }
    }

    /// The tab title, swapped for a text field while renaming.
    @ViewBuilder private var label: some View {
        if isRenaming {
            TextField("Tab Name", text: $renameText)
                .textFieldStyle(.plain)
                .font(.callout)
                .frame(minWidth: 60, maxWidth: 120)
                .focused($isRenameFieldFocused)
                .onSubmit {
                    commitRename()
                }
                .onChange(of: isRenameFieldFocused) { _, isFocused in
                    if !isFocused {
                        commitRename()
                    }
                }
        } else {
            Text(title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .help(directoryTooltip ?? title)
        }
    }

    /// Close button, revealed on hover or when the tab is selected.
    private var closeButton: some View {
        Button {
            model.requestCloseSession(id: session.id)
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .frame(width: 14, height: 14)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Close Tab")
        .opacity(isHovering || isSelected ? 1 : 0)
    }

    /// Accent stripe along the top edge of the active tab.
    private var accentStripe: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(height: 2)
            .opacity(isSelected ? 1 : 0)
    }

    /// Thin separator between tabs (hidden next to the active tab).
    private var separator: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.08))
            .frame(width: 1)
            .padding(.vertical, 6)
            .opacity(isSelected ? 0 : 1)
    }

    /// Fixed leading icon slot: the terminal glyph normally, replaced by
    /// the highest-priority status badge when there is one.
    @ViewBuilder private var leadingIcon: some View {
        if hasExited {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .help("Process exited")
        } else if controller.claudeStatus == .needsInput && !isSelected {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
                .help("Claude needs input")
        } else if controller.claudeStatus == .working {
            // Status, not attention: shown on the selected tab too.
            Image(systemName: "hourglass")
                .foregroundStyle(.secondary)
                .help("Claude is working")
        } else if controller.claudeStatus == .done {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("Claude is done")
        } else if controller.needsAttention && !isSelected {
            Image(systemName: "bell.fill")
                .foregroundStyle(.orange)
                .help("Needs attention")
        } else {
            Image(systemName: "terminal.fill")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var tabBackground: some View {
        if isSelected {
            terminalBackground
        } else if isHovering {
            Color.primary.opacity(0.06)
        } else {
            Color.clear
        }
    }

    private func beginRename() {
        renameText = session.customTitle ?? ""
        isRenaming = true
        isRenameFieldFocused = true
    }

    private func commitRename() {
        guard isRenaming else { return }
        isRenaming = false
        model.renameSession(id: session.id, customTitle: renameText)
    }
}
