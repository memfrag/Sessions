//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SessionsProtocol
import SwiftUI

/// Custom horizontal tab strip for the terminal sessions of a workspace.
struct TerminalTabBar: View {

    @Environment(WorkspacesModel.self) private var model

    @Environment(AppSettings.self) private var settings

    let workspace: Workspace

    let selectedSessionID: SessionInfo.ID?

    /// The active terminal background, so the selected tab merges into the
    /// content below it.
    private var terminalBackground: Color {
        let theme = TerminalTheme.theme(withID: settings.terminalThemeID, custom: settings.customTerminalThemes)
            .applying(settings.terminalThemeOverrides[settings.terminalThemeID])
        return Color(nsColor: theme.effectiveBackgroundColor)
    }

    var body: some View {
        HStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 0) {
                    ForEach(workspace.sessions) { session in
                        TerminalTabItem(
                            workspace: workspace,
                            session: session,
                            isSelected: session.id == selectedSessionID,
                            terminalBackground: terminalBackground
                        )
                    }
                }
            }
            newTabButton
        }
        .frame(height: 32)
        .background(alignment: .bottom) { barBackground }
    }

    private var newTabButton: some View {
        Button {
            model.createSession(in: workspace.id)
        } label: {
            Image(systemName: "plus")
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New Tab")
        .padding(.horizontal, 4)
    }

    /// The bar material plus a bottom hairline, both behind the tabs so the
    /// opaque selected tab paints over the line and merges with the content
    /// below.
    private var barBackground: some View {
        ZStack(alignment: .bottom) {
            Rectangle().fill(.bar)
            Rectangle()
                .fill(Color.primary.opacity(0.12))
                .frame(height: 1)
        }
    }
}
