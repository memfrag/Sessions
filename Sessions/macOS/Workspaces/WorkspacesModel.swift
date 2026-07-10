//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import Foundation
import Observation
import SessionsProtocol

/// Observable mirror of the server's workspace/session state, plus local
/// selection. All mutations are forwarded to the server; updated state
/// flows back via `stateChanged` broadcasts.
@Observable @MainActor
final class WorkspacesModel {

    private(set) var workspaces: [Workspace] = []

    var selectedWorkspaceID: Workspace.ID?

    /// Remembered tab selection per workspace.
    private var selectedSessionIDByWorkspace: [Workspace.ID: SessionInfo.ID] = [:]

    // MARK: UI state driven by menu commands and confirmation flows

    var isNewWorkspaceSheetPresented = false

    /// Whether the command palette overlay is shown. The terminal focus
    /// grab in `TerminalSessionView` yields while this is true.
    var isCommandPaletteVisible = false

    /// A snippet awaiting placeholder values before pasting, when triggered
    /// from the command palette. The main window hosts the fill sheet.
    var snippetPendingFill: Snippet?

    /// Tab close awaiting user confirmation because the session is busy.
    var sessionPendingClose: SessionInfo.ID?

    /// Workspace deletion awaiting user confirmation (has live sessions).
    var workspacePendingDelete: Workspace.ID?

    let serverManager: ServerManager

    let sessionRegistry: TerminalSessionRegistry

    init(serverManager: ServerManager) {
        self.serverManager = serverManager
        sessionRegistry = TerminalSessionRegistry(client: serverManager.client)
        serverManager.onStateChanged = { [weak self] state in
            self?.apply(state)
        }
        serverManager.onSessionExited = { [weak self] sessionID, exitCode in
            self?.sessionRegistry.noteExited(sessionID: sessionID, exitCode: exitCode)
        }
        serverManager.onConnected = { [weak self] in
            self?.sessionRegistry.reattachAll()
        }
        serverManager.start()
    }

    // MARK: - Lookup

    var selectedWorkspace: Workspace? {
        workspaces.first { $0.id == selectedWorkspaceID }
    }

    func selectedSessionID(in workspace: Workspace) -> SessionInfo.ID? {
        if let sessionID = selectedSessionIDByWorkspace[workspace.id],
           workspace.sessions.contains(where: { $0.id == sessionID }) {
            return sessionID
        }
        return workspace.sessions.first?.id
    }

    // MARK: - State sync

    private func apply(_ state: ServerState) {
        let previousSessionIDs = Set(workspaces.flatMap { $0.sessions.map(\.id) })
        workspaces = state.workspaces
        // Keep a valid workspace selection.
        if selectedWorkspaceID == nil || !workspaces.contains(where: { $0.id == selectedWorkspaceID }) {
            selectedWorkspaceID = workspaces.first?.id
        }
        // Select newly created tabs in their workspace.
        for workspace in workspaces {
            if let newSession = workspace.sessions.last(where: { !previousSessionIDs.contains($0.id) }) {
                selectedSessionIDByWorkspace[workspace.id] = newSession.id
            }
        }
        sessionRegistry.sync(with: state)
    }

    // MARK: - Workspace CRUD (forwarded to server)

    func createWorkspace(name: String, rootPath: String, startupCommand: String? = nil, colorID: String? = nil) {
        Task {
            await serverManager.client.createWorkspace(
                name: name,
                rootPath: rootPath,
                startupCommand: startupCommand,
                colorID: colorID
            )
        }
    }

    func renameWorkspace(id: Workspace.ID, name: String) {
        Task {
            await serverManager.client.renameWorkspace(id: id, name: name)
        }
    }

    func updateWorkspace(id: Workspace.ID, name: String, startupCommand: String?, colorID: String?) {
        Task {
            await serverManager.client.updateWorkspace(
                id: id,
                name: name,
                startupCommand: startupCommand,
                colorID: colorID
            )
        }
    }

    func deleteWorkspace(id: Workspace.ID) {
        Task {
            await serverManager.client.deleteWorkspace(id: id)
        }
    }

    /// Deletes immediately if the workspace has no live sessions; otherwise
    /// asks for confirmation first.
    func requestDeleteWorkspace(id: Workspace.ID) {
        let hasLiveSessions = workspaces
            .first { $0.id == id }?
            .sessions.contains { $0.isAlive } ?? false
        if hasLiveSessions {
            workspacePendingDelete = id
        } else {
            deleteWorkspace(id: id)
        }
    }

    func moveWorkspace(id: Workspace.ID, toIndex: Int) {
        Task {
            await serverManager.client.moveWorkspace(id: id, toIndex: toIndex)
        }
    }

    // MARK: - Session (tab) CRUD (forwarded to server)

    /// Opens a new tab, inheriting the current working directory of the
    /// selected tab when possible.
    func createSession(in workspaceID: Workspace.ID) {
        let inheritFrom = workspaces
            .first { $0.id == workspaceID }
            .flatMap { selectedSessionID(in: $0) }
        Task {
            await serverManager.client.createSession(
                workspaceID: workspaceID,
                inheritFromSessionID: inheritFrom
            )
        }
    }

    func closeSession(id: SessionInfo.ID) {
        Task {
            await serverManager.client.closeSession(id: id)
        }
    }

    /// Closes immediately if the session is dead or its shell is idle;
    /// asks for confirmation if a foreground process is running.
    func requestCloseSession(id: SessionInfo.ID) {
        guard let located = findSession(id: id), located.session.isAlive else {
            closeSession(id: id)
            return
        }
        Task {
            let isBusy = await serverManager.client.checkBusy(sessionID: id)
            if isBusy {
                sessionPendingClose = id
            } else {
                closeSession(id: id)
            }
        }
    }

    private func findSession(id: SessionInfo.ID) -> (workspace: Workspace, session: SessionInfo)? {
        for workspace in workspaces {
            if let session = workspace.sessions.first(where: { $0.id == id }) {
                return (workspace, session)
            }
        }
        return nil
    }

    func renameSession(id: SessionInfo.ID, customTitle: String?) {
        let title = customTitle?.trimmingCharacters(in: .whitespaces)
        let resolved = (title?.isEmpty ?? true) ? nil : title
        Task {
            await serverManager.client.renameSession(id: id, customTitle: resolved)
        }
    }

    func restartSession(id: SessionInfo.ID) {
        Task {
            await serverManager.client.restartSession(id: id)
        }
    }

    func moveSession(id: SessionInfo.ID, toIndex: Int) {
        Task {
            await serverManager.client.moveSession(id: id, toIndex: toIndex)
        }
    }

    /// Moves a session to another workspace (tab dragged onto a sidebar
    /// row). The moved tab becomes the target workspace's selection; the
    /// source selection self-heals via the membership check in
    /// `selectedSessionID(in:)`.
    func moveSessionToWorkspace(id: SessionInfo.ID, toWorkspace workspaceID: Workspace.ID) {
        guard findSession(id: id)?.workspace.id != workspaceID else { return }
        selectedSessionIDByWorkspace[workspaceID] = id
        Task {
            await serverManager.client.moveSessionToWorkspace(id: id, workspaceID: workspaceID)
        }
    }

    func selectSession(id: SessionInfo.ID, in workspaceID: Workspace.ID) {
        selectedSessionIDByWorkspace[workspaceID] = id
        sessionRegistry.controllerIfExists(for: id)?.clearAttention()
    }

    /// The folder name of the selected tab's working directory (from
    /// OSC 7), for display in the sidebar. Returns "~" for the home
    /// directory and nil when the cwd is unknown (no shell integration).
    func currentDirectoryName(for workspace: Workspace) -> String? {
        guard let sessionID = selectedSessionID(in: workspace),
              let directory = sessionRegistry.controllerIfExists(for: sessionID)?.currentDirectory else {
            return nil
        }
        if directory == NSHomeDirectory() {
            return "~"
        }
        let name = (directory as NSString).lastPathComponent
        return name.isEmpty ? directory : name
    }

    /// Display title for a session — the same chain the tab bar uses:
    /// custom title, shell title, cwd folder name, generic fallback.
    func sessionTitle(for session: SessionInfo) -> String {
        let controller = sessionRegistry.controllerIfExists(for: session.id)
        return session.customTitle
            ?? controller?.shellTitle
            ?? controller?.currentDirectory.map { ($0 as NSString).lastPathComponent }
            ?? "Terminal"
    }

    /// Sessions in the workspace that want the user's attention, for the
    /// menu bar's jump list.
    func attentionSessions(in workspace: Workspace) -> [SessionInfo] {
        workspace.sessions.filter { session in
            sessionRegistry.controllerIfExists(for: session.id)?.needsAttention ?? false
        }
    }

    /// Whether any session in the workspace wants the user's attention
    /// (bell or OSC 9 notification, e.g. Claude Code awaiting input).
    func workspaceNeedsAttention(_ workspace: Workspace) -> Bool {
        workspace.sessions.contains { session in
            sessionRegistry.controllerIfExists(for: session.id)?.needsAttention ?? false
        }
    }

    /// Whether any session in any workspace wants attention.
    var anyWorkspaceNeedsAttention: Bool {
        workspaces.contains { workspaceNeedsAttention($0) }
    }

    /// Highest-priority Claude status across the workspace's tabs
    /// (needs-input > working > done > none).
    func workspaceClaudeStatus(_ workspace: Workspace) -> TerminalSessionController.ClaudeStatus {
        workspace.sessions.reduce(.none) { status, session in
            max(status, sessionRegistry.controllerIfExists(for: session.id)?.claudeStatus ?? .none)
        }
    }

    /// Controller of the currently selected tab, if it exists.
    var selectedTerminalController: TerminalSessionController? {
        guard let workspace = selectedWorkspace,
              let sessionID = selectedSessionID(in: workspace) else { return nil }
        return sessionRegistry.controllerIfExists(for: sessionID)
    }

    // MARK: - Snippets

    /// Pastes a snippet into the active terminal. A snippet with
    /// placeholders is routed to the fill sheet first (hosted by the main
    /// window); a plain snippet is pasted immediately.
    func useSnippet(_ snippet: Snippet) {
        if snippet.placeholderNames.isEmpty {
            selectedTerminalController?.sendText(snippet.content)
        } else {
            snippetPendingFill = snippet
        }
    }

    /// Pastes already-substituted snippet text into the active terminal
    /// and dismisses the fill sheet.
    func pasteFilled(_ text: String) {
        selectedTerminalController?.sendText(text)
        snippetPendingFill = nil
    }

    // MARK: - Menu command actions (operate on the current selection)

    func newTabInSelectedWorkspace() {
        guard let workspace = selectedWorkspace else { return }
        createSession(in: workspace.id)
    }

    func closeSelectedTab() {
        guard let workspace = selectedWorkspace,
              let sessionID = selectedSessionID(in: workspace) else { return }
        requestCloseSession(id: sessionID)
    }

    func selectAdjacentTab(offset: Int) {
        guard let workspace = selectedWorkspace,
              !workspace.sessions.isEmpty,
              let currentID = selectedSessionID(in: workspace),
              let currentIndex = workspace.sessions.firstIndex(where: { $0.id == currentID }) else {
            return
        }
        let count = workspace.sessions.count
        let nextIndex = (currentIndex + offset + count) % count
        selectSession(id: workspace.sessions[nextIndex].id, in: workspace.id)
    }

    func selectTab(atIndex index: Int) {
        guard let workspace = selectedWorkspace,
              workspace.sessions.indices.contains(index) else { return }
        selectSession(id: workspace.sessions[index].id, in: workspace.id)
    }

    /// Whether the workspace's root directory is missing on disk (shown as
    /// a warning badge; new tabs fall back to the home directory).
    func isRootMissing(for workspace: Workspace) -> Bool {
        var isDirectory = ObjCBool(false)
        let exists = FileManager.default.fileExists(atPath: workspace.rootPath, isDirectory: &isDirectory)
        return !(exists && isDirectory.boolValue)
    }
}
