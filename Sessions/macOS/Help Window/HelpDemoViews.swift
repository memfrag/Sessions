//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import SwiftUI

// Self-contained mock views embedded in the Markdown help document via
// `<view tag="…" />`. They use static example data so they render
// identically regardless of app state.

/// A small strip of mock tabs showing the status badges.
struct HelpTabBarDemo: View {
    var body: some View {
        HStack(spacing: 6) {
            demoTab(icon: "terminal.fill", title: "server", color: .secondary, selected: true)
            demoTab(icon: "hourglass", title: "build", color: .secondary, selected: false)
            demoTab(icon: "bell.fill", title: "deploy", color: .orange, selected: false)
            demoTab(icon: "checkmark.circle.fill", title: "tests", color: .green, selected: false)
        }
        .padding(.vertical, 4)
    }

    private func demoTab(icon: String, title: String, color: Color, selected: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(color)
            Text(title)
                .font(.callout)
                .foregroundStyle(selected ? .primary : .secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.primary.opacity(0.08) : .clear)
        )
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 2)
                .opacity(selected ? 1 : 0)
        }
    }
}

/// Legend of the three Claude Code status badges.
struct HelpClaudeStatusLegend: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            row("hourglass", .secondary, "Working", "Claude is thinking or running.")
            row("bell.fill", .orange, "Needs input", "Claude is waiting for you — the tab and workspace light up.")
            row("checkmark.circle.fill", .green, "Done", "Claude finished its turn.")
        }
        .padding(.vertical, 4)
    }

    private func row(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 18)
            Text(title).fontWeight(.medium)
            Text(detail).foregroundStyle(.secondary)
        }
    }
}

/// A snippet with its `{{placeholder}}` tokens highlighted, as shown in the
/// snippet editor.
struct HelpSnippetDemo: View {
    var body: some View {
        Text(styled)
            .font(.body.monospaced())
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.primary.opacity(0.05))
            )
            .padding(.vertical, 4)
    }

    private var styled: AttributedString {
        var result = AttributedString("ssh ")
        result += token("{{user}}")
        result += AttributedString("@")
        result += token("{{host:localhost}}")
        result += AttributedString(" -p ")
        result += token("{{port:22}}")
        return result
    }

    private func token(_ text: String) -> AttributedString {
        var token = AttributedString(text)
        token.foregroundColor = .accentColor
        return token
    }
}

/// A mock command-palette panel.
struct HelpPaletteDemo: View {
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                Text("new tab").font(.title3)
                Spacer()
            }
            .padding(10)
            Divider()
            paletteRow("plus.rectangle", "New Tab", "⌘T", selected: true)
            paletteRow("folder", "Filmstack", "Switch to Workspace", selected: false)
            paletteRow("text.append", "Deploy Script", "Paste Snippet", selected: false)
        }
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color(nsColor: .windowBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Color.primary.opacity(0.15), lineWidth: 1)
        )
        .padding(.vertical, 6)
    }

    private func paletteRow(_ icon: String, _ title: String, _ hint: String, selected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .frame(width: 20)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            Text(title)
                .foregroundStyle(selected ? AnyShapeStyle(.white) : AnyShapeStyle(.primary))
            Spacer()
            Text(hint)
                .font(.callout)
                .foregroundStyle(selected ? AnyShapeStyle(.white.opacity(0.8)) : AnyShapeStyle(.secondary))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(selected ? Color.accentColor : .clear)
        )
        .padding(.horizontal, 6)
        .padding(.vertical, 1)
    }
}

/// The workspace accent-color palette.
struct HelpWorkspaceColorsDemo: View {
    var body: some View {
        HStack(spacing: 10) {
            ForEach(WorkspaceColor.palette) { entry in
                Circle()
                    .fill(entry.color)
                    .frame(width: 18, height: 18)
                    .help(entry.name)
            }
        }
        .padding(.vertical, 4)
    }
}

/// A grid of the app's keyboard shortcuts.
struct HelpShortcutsGrid: View {
    private static let shortcuts: [(keys: String, action: String)] = [
        ("⇧⌘P", "Command palette"),
        ("⇧⌘S", "Snippets window"),
        ("⇧⌘N", "New workspace"),
        ("⌘T", "New tab"),
        ("⌘W", "Close tab"),
        ("⌘1 – ⌘9", "Select tab by position"),
        ("⇧⌘]  /  ⇧⌘[", "Next / previous tab"),
        ("⌘F", "Find in terminal"),
        ("⌘G  /  ⇧⌘G", "Find next / previous"),
        ("⌥⌘Q", "Quit and stop all sessions")
    ]

    var body: some View {
        Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 6) {
            ForEach(Self.shortcuts, id: \.keys) { shortcut in
                GridRow {
                    Text(shortcut.keys)
                        .font(.body.monospaced())
                        .foregroundStyle(.secondary)
                    Text(shortcut.action)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
