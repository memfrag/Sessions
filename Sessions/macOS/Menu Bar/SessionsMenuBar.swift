//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Menu bar status item: server health and live sessions at a glance.
/// The app keeps running with the last window closed; this is the way
/// back in.
struct SessionsMenuBar: Scene {

    let workspacesModel: WorkspacesModel

    var body: some Scene {
        MenuBarExtra {
            SessionsMenuBarView()
                .environment(workspacesModel)
        } label: {
            Image(
                systemName: workspacesModel.anyWorkspaceNeedsAttention
                    ? "bell.badge.fill"
                    : "terminal"
            )
        }
        .menuBarExtraStyle(.window)
    }
}

private struct SessionsMenuBarView: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(\.openWindow) private var openWindow

    private var liveSessionCount: Int {
        model.workspaces.reduce(0) { count, workspace in
            count + workspace.sessions.count { $0.isAlive }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            serverStatusRow
            Divider()
            if model.workspaces.isEmpty {
                Text("No workspaces")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.workspaces) { workspace in
                    workspaceRow(workspace)
                }
            }
            Divider()
            Button {
                openMainWindow()
            } label: {
                Label("Open Sessions", systemImage: "macwindow")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.serverManager.restartServer()
            } label: {
                Label("Restart Server", systemImage: "arrow.clockwise")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Ends all running sessions and starts a fresh server. The workspace layout is kept.")
            .disabled(model.serverManager.status != .connected)
            Divider()
            Button {
                // Detaches only; shells keep running in the server.
                NSApplication.shared.terminate(nil)
            } label: {
                Label("Quit App", systemImage: "power")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            Button {
                model.serverManager.closeAllSessionsAndQuit()
            } label: {
                Label("Quit and Stop All Sessions", systemImage: "power.circle.fill")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 260)
    }

    private var serverStatusRow: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(serverStatusColor)
                .frame(width: 9, height: 9)
            Text(serverStatusText)
                .fontWeight(.medium)
            Spacer()
            if liveSessionCount > 0 {
                Text("\(liveSessionCount) live")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
        }
    }

    private var serverStatusColor: Color {
        switch model.serverManager.status {
        case .connected: .green
        case .connecting, .idle: .yellow
        case .needsApproval, .failed: .red
        }
    }

    private var serverStatusText: String {
        switch model.serverManager.status {
        case .connected: "Server running"
        case .connecting: "Connecting to server…"
        case .idle: "Starting…"
        case .needsApproval: "Needs approval"
        case .failed: "Server unavailable"
        }
    }

    private func workspaceRow(_ workspace: Workspace) -> some View {
        Button {
            model.selectedWorkspaceID = workspace.id
            openMainWindow()
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "terminal")
                    .foregroundStyle(.secondary)
                Text(workspace.name)
                    .lineLimit(1)
                if model.workspaceNeedsAttention(workspace) {
                    Image(systemName: "bell.fill")
                        .font(.caption2)
                        .foregroundStyle(.orange)
                }
                Spacer()
                let live = workspace.sessions.count { $0.isAlive }
                Text(live > 0 ? "\(live) live" : "\(workspace.sessions.count) tabs")
                    .font(.caption)
                    .foregroundStyle(live > 0 ? Color.green : Color.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func openMainWindow() {
        openWindow(id: MainWindow.windowID)
        NSApplication.shared.activate()
    }
}
