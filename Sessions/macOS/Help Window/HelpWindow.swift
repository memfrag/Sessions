//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI
import MarkdownUI

public struct HelpWindow: Scene {

    public static let windowID = "help"
            
    public var body: some Scene {
        Window("Sessions Help", id: Self.windowID) {
            HelpContent()
                .frame(minWidth: 560, minHeight: 460)
        }
        .commandsRemoved() // Don't show window in Windows menu
        .defaultPosition(.center)
        .defaultSize(width: 680, height: 640)
        .windowResizability(.contentMinSize)
    }
}

/// The help window's content: user documentation authored in Markdown with
/// live SwiftUI demo views embedded via `<view tag="…" />` blocks.
struct HelpContent: View {

    private static let document = try? MarkdownDocument(markdown)

    var body: some View {
        ScrollView {
            if let document = Self.document {
                Markdown(document, lazy: false) { tag in
                    switch tag {
                    case "tabbar": HelpTabBarDemo()
                    case "claude-status": HelpClaudeStatusLegend()
                    case "snippet": HelpSnippetDemo()
                    case "palette": HelpPaletteDemo()
                    case "workspace-colors": HelpWorkspaceColorsDemo()
                    case "shortcuts": HelpShortcutsGrid()
                    default: EmptyView()
                    }
                }
                .markdownStyle(MarkdownStyle())
                .textSelection(.enabled)
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Help is unavailable.")
                    .foregroundStyle(.secondary)
                    .padding(28)
            }
        }
    }

    private static let markdown = #"""
    # Sessions Help

    Sessions is a terminal multiplexer: a sidebar of **workspaces**, each with
    its own **tabs**, and every tab a live terminal. Your shells keep running
    even if the app crashes or you quit — so you can close the window and come
    right back to where you were.

    ## Workspaces & Tabs

    A **workspace** groups terminal tabs under a name and a root directory. New
    tabs open in the current tab's working directory when shell integration is
    on, otherwise in the workspace root.

    Give a workspace an accent color to tell it apart at a glance:

    <view tag="workspace-colors" />

    Right-click a workspace for **Edit Workspace…**, where you can set its
    color and a **startup command** that runs in every new tab (e.g. `claude`
    or a dev server). Drag a tab onto another workspace in the sidebar to move
    it there — the shell keeps running.

    ## The Session Server

    Your shells don't run inside this app. They live in a separate background
    process — the **session server** — that survives app crashes, quits, and
    updates, like tmux. This is what makes Sessions crash-resilient.

    - **Quit App** — the window closes but shells keep running; reopening
      reconnects and replays each tab.
    - **Restart Server** — terminates the shells but keeps your workspaces and
      tabs; used after an update.
    - **Quit and Stop All Sessions** — a clean slate: every shell ends.

    Scrollback is even restored after a graceful server restart or a reboot.

    ## Command Palette

    Press **⇧⌘P** for a searchable list of everything: actions, every
    workspace and tab, themes, and your snippets. Type to fuzzy-filter, then
    press Return.

    <view tag="palette" />

    ## Snippets

    Snippets are reusable text you paste into the active terminal. Open the
    manager with **⇧⌘S**, or use the toolbar's **Snippets** menu. Double-click
    a snippet (or the command palette) to paste it — no newline is added, so
    you can edit before running.

    Snippets can contain `{{placeholders}}` with optional defaults; you're
    prompted for each value before pasting:

    <view tag="snippet" />

    ## Claude Code

    Running `claude` in a tab reports its state through hooks that Sessions
    loads automatically in zsh. The tab, sidebar, and menu bar show:

    <view tag="claude-status" />

    Typing in a tab clears its badge. See **Settings › General** to also get
    Notification Center alerts.

    Here is how the badges look across a row of tabs:

    <view tag="tabbar" />

    ## Themes & Appearance

    **Settings › Theme** offers built-in palettes and per-theme color
    overrides, and can **import iTerm2 `.itermcolors`** files. **Settings ›
    Appearance** sets the font, cursor, scrollback size, and the paste-safety
    and Metal-renderer options.

    ## Shell Integration

    For zsh (the macOS default), Sessions configures integration
    automatically: the shell reports its working directory so new tabs open in
    the right place, tab titles follow the current folder, and *Reveal in
    Finder* / *Open Current Directory in Finder* know where to go. For other
    shells, **Settings › General** has a snippet to add manually.

    ## Keyboard Shortcuts

    <view tag="shortcuts" />
    """#
}
