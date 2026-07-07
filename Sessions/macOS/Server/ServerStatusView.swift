//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// Overlay for the session-server connection state: a small banner while
/// connecting or failed, and a full-pane blocked state while the launchd
/// agent awaits approval in System Settings.
struct ServerStatusView: View {

    @Environment(WorkspacesModel.self) private var model

    let status: ServerManager.Status

    var body: some View {
        switch status {
        case .idle, .connected:
            EmptyView()
        case .connecting:
            banner {
                ProgressView()
                    .controlSize(.small)
                Text("Connecting to session server…")
            }
        case .needsApproval:
            approvalPane
        case .failed(let message):
            banner {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(message)
            }
        }
    }

    /// Full-pane blocked state: terminals cannot work until the background
    /// helper is approved.
    private var approvalPane: some View {
        VStack(spacing: 16) {
            Image(systemName: "lock.shield")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
            Text("Approval Required")
                .font(.title2)
                .fontWeight(.semibold)
            Text("""
            Sessions runs your terminals in a background helper so they \
            survive if the app crashes. macOS requires your approval: \
            allow “Sessions” under Login Items & Extensions.
            """)
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(maxWidth: 420)
            Button("Open System Settings") {
                model.serverManager.openLoginItemsSettings()
            }
            .keyboardShortcut(.defaultAction)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }

    private func banner(@ViewBuilder content: () -> some View) -> some View {
        VStack {
            HStack(spacing: 8) {
                content()
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .padding()
            Spacer()
        }
    }
}
