//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SessionsProtocol
import SwiftUI

struct Sidebar: View {

    @Environment(WorkspacesModel.self) private var model

    @State private var workspaceToRename: Workspace?

    @State private var renameText = ""

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            List(selection: $model.selectedWorkspaceID) {
                Section(header: Text("Workspaces")) {
                    ForEach(model.workspaces) { workspace in
                        NavigationLink(value: workspace.id) {
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 6) {
                                    Label(workspace.name, systemImage: "terminal")
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
                                        .padding(.leading, 24)
                                }
                            }
                            .badge(
                                model.isRootMissing(for: workspace)
                                    ? Text(Image(systemName: "exclamationmark.triangle.fill"))
                                    : nil
                            )
                        }
                        .contextMenu {
                            Button("Rename…") {
                                renameText = workspace.name
                                workspaceToRename = workspace
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
                    .onMove { source, destination in
                        moveWorkspaces(from: source, to: destination)
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(minWidth: 180, idealWidth: 200, maxWidth: 300)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                SidebarFooter {
                    model.isNewWorkspaceSheetPresented = true
                }
            }
        } detail: {
            ZStack(alignment: .top) {
                if let workspace = model.selectedWorkspace {
                    WorkspacePane(workspace: workspace)
                        .id(workspace.id)
                } else {
                    EmptyPane()
                }
                ServerStatusView(status: model.serverManager.status)
            }
        }
        .focusedSceneValue(\.workspacesModel, model)
        .sheet(isPresented: $model.isNewWorkspaceSheetPresented) {
            NewWorkspaceSheet()
        }
        .alert("Rename Workspace", isPresented: renameAlertPresented) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let workspace = workspaceToRename {
                    model.renameWorkspace(id: workspace.id, name: renameText)
                }
                workspaceToRename = nil
            }
            Button("Cancel", role: .cancel) {
                workspaceToRename = nil
            }
        }
        .confirmationDialog(
            "This tab has a running process. Close it anyway?",
            isPresented: pendingCloseDialogPresented
        ) {
            Button("Close Tab", role: .destructive) {
                if let sessionID = model.sessionPendingClose {
                    model.closeSession(id: sessionID)
                }
                model.sessionPendingClose = nil
            }
            Button("Cancel", role: .cancel) {
                model.sessionPendingClose = nil
            }
        } message: {
            Text("The running process will be terminated.")
        }
        .confirmationDialog(
            "Delete this workspace and terminate its running sessions?",
            isPresented: pendingDeleteDialogPresented
        ) {
            Button("Delete Workspace", role: .destructive) {
                if let workspaceID = model.workspacePendingDelete {
                    model.deleteWorkspace(id: workspaceID)
                }
                model.workspacePendingDelete = nil
            }
            Button("Cancel", role: .cancel) {
                model.workspacePendingDelete = nil
            }
        } message: {
            Text("All terminal sessions in the workspace will be terminated.")
        }
    }

    private func moveWorkspaces(from source: IndexSet, to destination: Int) {
        guard let sourceIndex = source.first,
              model.workspaces.indices.contains(sourceIndex) else { return }
        let workspace = model.workspaces[sourceIndex]
        let targetIndex = destination > sourceIndex ? destination - 1 : destination
        model.moveWorkspace(id: workspace.id, toIndex: targetIndex)
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding {
            workspaceToRename != nil
        } set: { isPresented in
            if !isPresented {
                workspaceToRename = nil
            }
        }
    }

    private var pendingCloseDialogPresented: Binding<Bool> {
        Binding {
            model.sessionPendingClose != nil
        } set: { isPresented in
            if !isPresented {
                model.sessionPendingClose = nil
            }
        }
    }

    private var pendingDeleteDialogPresented: Binding<Bool> {
        Binding {
            model.workspacePendingDelete != nil
        } set: { isPresented in
            if !isPresented {
                model.workspacePendingDelete = nil
            }
        }
    }
}

#Preview {
    Sidebar()
        .environment(WorkspacesModel(serverManager: ServerManager()))
}
