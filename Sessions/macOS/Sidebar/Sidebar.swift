//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

struct Sidebar: View {

    @Environment(WorkspacesModel.self) private var model

    @State private var workspaceToRename: Workspace?

    @State private var workspaceToEdit: Workspace?

    @State private var renameText = ""

    @State private var filterText = ""

    /// Workspaces matching the footer filter: fuzzy match against the
    /// workspace name, its tab titles, and its tabs' current directory
    /// folder names. Sidebar order is preserved (filter, not ranking).
    private var filteredWorkspaces: [Workspace] {
        let trimmed = filterText.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return model.workspaces }
        return model.workspaces.filter { workspace in
            if FuzzyMatch.matches(query: trimmed, in: workspace.name) {
                return true
            }
            return workspace.sessions.contains { session in
                if FuzzyMatch.matches(query: trimmed, in: model.sessionTitle(for: session)) {
                    return true
                }
                guard let directory = model.sessionRegistry
                    .controllerIfExists(for: session.id)?.currentDirectory else {
                    return false
                }
                return FuzzyMatch.matches(query: trimmed, in: (directory as NSString).lastPathComponent)
            }
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationSplitView {
            sidebarList
        } detail: {
            detailPane
        }
        .overlay {
            if model.isCommandPaletteVisible {
                CommandPaletteOverlay()
            }
        }
        .navigationTitle(model.selectedWorkspace?.name ?? "Sessions")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                SnippetsToolbarMenu()
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .focusedSceneValue(\.workspacesModel, model)
        .sheet(isPresented: $model.isNewWorkspaceSheetPresented) {
            NewWorkspaceSheet()
        }
        .sheet(item: $workspaceToEdit) { workspace in
            EditWorkspaceSheet(workspace: workspace)
        }
        .sheet(item: $model.snippetPendingFill) { snippet in
            SnippetFillSheet(snippet: snippet) { text in
                model.pasteFilled(text)
            }
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

    private var sidebarList: some View {
        @Bindable var model = model
        return List(selection: $model.selectedWorkspaceID) {
            Section(header: Text("Workspaces")) {
                ForEach(filteredWorkspaces) { workspace in
                    WorkspaceSidebarItem(workspace: workspace) { workspace in
                        renameText = workspace.name
                        workspaceToRename = workspace
                    } onEdit: { workspace in
                        workspaceToEdit = workspace
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
            SidebarFooter(filterText: $filterText) {
                model.isNewWorkspaceSheetPresented = true
            }
        }
    }

    private var detailPane: some View {
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

    private func moveWorkspaces(from source: IndexSet, to destination: Int) {
        // Row indices refer to the filtered list; reordering a filtered
        // subset is ill-defined, so it is disabled while filtering.
        guard filterText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
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
