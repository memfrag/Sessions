//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Detail pane for a workspace: tab bar on top, terminals below.
///
/// All of the workspace's terminals stay in the view hierarchy (hidden via
/// opacity) so switching tabs never tears down a terminal view or its
/// server attachment.
struct WorkspacePane: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    var body: some View {
        let selectedSessionID = model.selectedSessionID(in: workspace)
        VStack(spacing: 0) {
            TerminalTabBar(workspace: workspace, selectedSessionID: selectedSessionID)
            Divider()
            if workspace.sessions.isEmpty {
                emptyState
            } else {
                ZStack {
                    ForEach(workspace.sessions) { session in
                        TerminalSessionPage(
                            session: session,
                            isSelected: session.id == selectedSessionID
                        )
                        .opacity(session.id == selectedSessionID ? 1 : 0)
                        .allowsHitTesting(session.id == selectedSessionID)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Text("No terminal tabs")
                .foregroundStyle(.secondary)
            Button("New Tab") {
                model.createSession(in: workspace.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// One terminal page: the terminal view plus a restart overlay when the
/// shell has exited. Dormant sessions (dead but never exited, e.g. after
/// a reboot) restart automatically when they become selected.
private struct TerminalSessionPage: View {

    @Environment(WorkspacesModel.self) private var model

    let session: SessionInfo

    let isSelected: Bool

    private var hasExited: Bool {
        !session.isAlive && session.exitCode != nil
    }

    private var isDormant: Bool {
        !session.isAlive && session.exitCode == nil
    }

    var body: some View {
        let controller = model.sessionRegistry.controller(for: session.id)
        TerminalSessionView(controller: controller, isSelected: isSelected && !hasExited)
            .overlay(alignment: .topTrailing) {
                if isSelected && controller.isFindBarVisible {
                    TerminalFindBar(controller: controller)
                        .padding(8)
                }
            }
            .overlay {
                if hasExited {
                    exitedOverlay
                }
            }
            .onAppear {
                restartIfDormant()
            }
            .onChange(of: isSelected) { _, selected in
                if selected {
                    restartIfDormant()
                }
            }
    }

    private func restartIfDormant() {
        guard isSelected, isDormant else { return }
        model.restartSession(id: session.id)
    }

    private var exitedOverlay: some View {
        VStack(spacing: 12) {
            if let exitCode = session.exitCode {
                Text("Process exited with code \(exitCode)")
            } else {
                Text("Process exited")
            }
            Button("Restart") {
                model.restartSession(id: session.id)
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}
