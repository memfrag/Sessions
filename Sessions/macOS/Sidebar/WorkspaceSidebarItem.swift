//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SessionsProtocol
import SwiftUI

/// A single workspace row in the sidebar: name, attention/missing-root
/// badges, the selected tab's working directory, and a context menu.
struct WorkspaceSidebarItem: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    /// Invoked when the user chooses "Rename…"; the sidebar owns the rename
    /// alert state.
    let onRename: (Workspace) -> Void

    /// Invoked when the user chooses "Edit Workspace…"; the sidebar owns
    /// the edit sheet state.
    let onEdit: (Workspace) -> Void

    @State private var isDropTargeted = false

    var body: some View {
        NavigationLink(value: workspace.id) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    if let color = WorkspaceColor.color(forID: workspace.colorID) {
                        Circle()
                            .fill(color)
                            .frame(width: 8, height: 8)
                    }
                    Text(workspace.name)
                        .fontWeight(.medium)
                    if model.workspaceNeedsAttention(workspace) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("A session needs attention")
                    } else if model.workspaceClaudeStatus(workspace) == .working {
                        Image(systemName: "hourglass")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .help("Claude is working")
                    } else if model.workspaceClaudeStatus(workspace) == .done {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.green)
                            .help("Claude is done")
                    }
                }
                if let directory = model.currentDirectoryName(for: workspace) {
                    Text(directory)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .padding(.top, 2)
                }
            }
            .padding(2)
            .badge(
                model.isRootMissing(for: workspace)
                    ? Text(Image(systemName: "exclamationmark.triangle.fill"))
                    : nil
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            // Tabs are draggable as session-ID strings; dropping one here
            // moves the session into this workspace.
            .dropDestination(for: String.self) { items, _ in
                guard let sessionID = items.first.flatMap(UUID.init) else { return false }
                model.moveSessionToWorkspace(id: sessionID, toWorkspace: workspace.id)
                return true
            } isTargeted: { targeting in
                isDropTargeted = targeting
            }
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.accentColor.opacity(isDropTargeted ? 0.2 : 0))
            )
        }
        .contextMenu {
            Button("Rename…") {
                onRename(workspace)
            }
            Button("Edit Workspace…") {
                onEdit(workspace)
            }
            Button("Reveal in Finder") {
                NSWorkspace.shared.selectFile(
                    nil,
                    inFileViewerRootedAtPath: workspace.rootPath
                )
            }
            Divider()
            Button("Delete Workspace", role: .destructive) {
                model.requestDeleteWorkspace(id: workspace.id)
            }
        }
    }
}
