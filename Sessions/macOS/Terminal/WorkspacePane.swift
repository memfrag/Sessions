//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Detail pane for a workspace: tab bar on top, terminals below.
///
/// Every tab's terminal view stays mounted and correctly sized, so
/// switching never remounts or reflows a terminal. The selected tab is
/// brought to the front with `zIndex` while every tab keeps full opacity
/// — hiding via `opacity(0)` let AppKit drop a hidden view's layer
/// backing store, which came back blank on reselect. The opaque selected
/// terminal simply covers the others.
struct WorkspacePane: View {

    @Environment(WorkspacesModel.self) private var model

    let workspace: Workspace

    var body: some View {
        let selectedSessionID = model.selectedSessionID(in: workspace)
        VStack(spacing: 0) {
            TerminalTabBar(workspace: workspace, selectedSessionID: selectedSessionID)
            if workspace.sessions.isEmpty {
                emptyState
            } else {
                ZStack {
                    ForEach(workspace.sessions) { session in
                        let isSelected = session.id == selectedSessionID
                        TerminalSessionPage(session: session, isSelected: isSelected)
                            .zIndex(isSelected ? 1 : 0)
                            .allowsHitTesting(isSelected)
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
            .onChange(of: isSelected) { _, selected in
                if selected {
                    restartIfDormant()
                    // Belt and suspenders: repaint from the buffer in case
                    // this tab was occluded when new output arrived.
                    controller.forceRedraw()
                }
            }
            .onAppear {
                restartIfDormant()
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
