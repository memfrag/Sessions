//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Custom horizontal tab strip for the terminal sessions of a workspace.
struct TerminalTabBar: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    let selectedSessionID: SessionInfo.ID?

    var body: some View {
        HStack(spacing: 4) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(workspace.sessions) { session in
                        TerminalTabItem(
                            workspace: workspace,
                            session: session,
                            isSelected: session.id == selectedSessionID
                        )
                    }
                }
                .padding(.horizontal, 8)
            }
            Button {
                model.createSession(in: workspace.id)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("New Tab")
            .padding(.trailing, 8)
        }
        .frame(height: 34)
        .background(.bar)
    }
}

/// One tab in the tab strip: title, dead/bell badges, close-on-hover,
/// double-click to rename.
private struct TerminalTabItem: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    let session: SessionInfo

    let isSelected: Bool

    @State private var isHovering = false

    @State private var isRenaming = false

    @State private var renameText = ""

    @FocusState private var isRenameFieldFocused: Bool

    private var controller: TerminalSessionController {
        model.sessionRegistry.controller(for: session.id)
    }

    private var title: String {
        session.customTitle
            ?? controller.shellTitle
            ?? controller.currentDirectory.map { ($0 as NSString).lastPathComponent }
            ?? "Terminal"
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
            if hasExited {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Process exited")
            } else if controller.needsAttention && !isSelected {
                Image(systemName: "bell.fill")
                    .font(.caption2)
                    .foregroundStyle(.orange)
                    .help("Needs attention")
            }
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
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isSelected ? Color.primary.opacity(0.15) : Color.clear)
        )
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
