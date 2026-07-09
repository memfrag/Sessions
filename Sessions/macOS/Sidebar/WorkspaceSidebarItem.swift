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

    var body: some View {
        NavigationLink(value: workspace.id) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(workspace.name)
                        .fontWeight(.medium)
                    if model.workspaceNeedsAttention(workspace) {
                        Image(systemName: "bell.fill")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .help("A session needs attention")
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
        }
        .contextMenu {
            Button("Rename…") {
                onRename(workspace)
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
