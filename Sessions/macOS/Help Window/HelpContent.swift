//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

/// The help window's content: keyboard shortcuts, integrations, and the
/// session-server model. Static and scrollable.
struct HelpContent: View {

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                shortcutsSection
                Divider()
                claudeSection
                Divider()
                shellIntegrationSection
                Divider()
                serverSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Keyboard shortcuts

    private static let shortcuts: [(keys: String, action: String)] = [
        ("⇧⌘P", "Command palette"),
        ("⇧⌘N", "New workspace"),
        ("⌘T", "New tab"),
        ("⌘W", "Close tab"),
        ("⇧⌘W", "Close window"),
        ("⌘1 – ⌘9", "Select tab by position"),
        ("⇧⌘]  /  ⇧⌘[", "Next / previous tab"),
        ("⌘F", "Find in terminal"),
        ("⌘G  /  ⇧⌘G", "Find next / previous"),
        ("⌥⌘Q", "Quit and stop all sessions")
    ]

    private var shortcutsSection: some View {
        section("Keyboard Shortcuts") {
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                ForEach(Self.shortcuts, id: \.keys) { shortcut in
                    GridRow {
                        Text(shortcut.keys)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Text(shortcut.action)
                    }
                }
            }
        }
    }

    // MARK: Claude Code

    private var claudeSection: some View {
        section("Claude Code") {
            Text("""
            Running `claude` in a tab reports its state through hooks that \
            Sessions loads automatically in zsh. Tabs, the sidebar, and the \
            menu bar show:
            """)
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 6) {
                GridRow {
                    Image(systemName: "hourglass").foregroundStyle(.secondary)
                    Text("Claude is working")
                }
                GridRow {
                    Image(systemName: "bell.fill").foregroundStyle(.orange)
                    Text("Claude needs your input")
                }
                GridRow {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text("Claude is done")
                }
            }
            Text("""
            Typing in the tab clears its badge. Needs-input can also post a \
            Notification Center notification — see Settings › General. The \
            menu bar lists tabs that want attention; click one to jump there.
            """)
        }
    }

    // MARK: Shell integration

    private var shellIntegrationSection: some View {
        section("Shell Integration") {
            Text("""
            For zsh (the macOS default), Sessions configures integration \
            automatically: the shell reports its working directory, so new \
            tabs open where you are, tab titles follow the current folder, \
            and “Open Current Directory in Finder” knows where to go. For \
            other shells, Settings › General has a snippet to add manually.
            """)
        }
    }

    // MARK: Session server

    private var serverSection: some View {
        section("The Session Server") {
            Text("""
            Your shells do not run inside this app. They live in a separate \
            background process — the session server — that survives app \
            crashes, quits, and updates, like tmux. Closing the window or \
            quitting the app leaves everything running; reopening the app \
            reconnects and replays each tab, and scrollback is even restored \
            after a clean restart of the server or a reboot.
            """)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                GridRow {
                    Text("Quit App").fontWeight(.medium)
                    Text("Shells keep running; reconnect on next launch")
                }
                GridRow {
                    Text("Restart Server").fontWeight(.medium)
                    Text("Shells terminate; workspaces and tabs are kept")
                }
                GridRow {
                    Text("Quit and Stop All Sessions").fontWeight(.medium)
                    Text("Everything terminates; clean slate")
                }
            }
        }
    }

    // MARK: Helpers

    private func section(
        _ title: String,
        @ViewBuilder content: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.weight(.semibold))
            content()
        }
    }
}
