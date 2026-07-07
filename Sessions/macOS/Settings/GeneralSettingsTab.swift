//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

struct GeneralSettingsTab: View {

    /// Claude Code hook that signals "needs attention" via OSC 9. Hooks run
    /// detached from the controlling terminal, so this writes to the
    /// terminal device by the path captured in SESSIONS_TTY (set by the
    /// shell integration), falling back to /dev/tty.
    static let claudeCodeHookSnippet = """
    {
      "hooks": {
        "Notification": [
          { "hooks": [ { "type": "command",
            "command": "printf '\\\\033]9;Claude needs input\\\\007' > \\"${SESSIONS_TTY:-/dev/tty}\\"" } ] }
        ],
        "Stop": [
          { "hooks": [ { "type": "command",
            "command": "printf '\\\\033]9;Claude is done\\\\007' > \\"${SESSIONS_TTY:-/dev/tty}\\"" } ] }
        ]
      }
    }
    """

    /// zsh snippet enabling OSC 7 cwd reporting, modeled on Apple's
    /// /etc/zshrc_Apple_Terminal (byte-wise percent-encoding with
    /// LC_CTYPE=C so UTF-8 paths encode correctly).
    static let shellIntegrationSnippet = """
    # Sessions terminal: report working directory via OSC 7
    if [[ "$TERM_PROGRAM" == "Sessions" ]]; then
        export SESSIONS_TTY="$(tty 2>/dev/null)"
        __sessions_update_cwd() {
            local url_path='' i ch hexch LC_CTYPE=C LC_COLLATE=C LC_ALL= LANG=
            for ((i = 1; i <= ${#PWD}; ++i)); do
                ch="$PWD[i]"
                if [[ "$ch" =~ [/._~A-Za-z0-9-] ]]; then
                    url_path+="$ch"
                else
                    printf -v hexch "%02X" "'$ch"
                    url_path+="%$hexch"
                fi
            done
            printf '\\e]7;%s\\a' "file://$HOST$url_path"
        }
        autoload -Uz add-zsh-hook
        add-zsh-hook precmd __sessions_update_cwd
    fi
    """

    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings
        Form {
            Section("Shell Integration") {
                Text("""
                Sessions follows your shell's working directory to open new \
                tabs in the right place and show the directory in tab \
                tooltips. This is set up automatically for zsh. For other \
                shells, add the equivalent of this to your shell config:
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(Self.shellIntegrationSnippet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 150)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
                Button("Copy Snippet") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(Self.shellIntegrationSnippet, forType: .string)
                }
            }
            Section("Claude Code Integration") {
                Text("""
                When Claude Code needs your input, Sessions highlights the \
                tab and workspace with a bell badge. In zsh this works \
                automatically — the `claude` command is wrapped to load the \
                attention hooks. For other shells, merge this hook into \
                ~/.claude/settings.json:
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
                ScrollView(.horizontal) {
                    Text(Self.claudeCodeHookSnippet)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                }
                .frame(maxHeight: 130)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.primary.opacity(0.05))
                )
                Button("Copy Hook") {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(Self.claudeCodeHookSnippet, forType: .string)
                }
                Toggle(
                    "Also show Notification Center alerts",
                    isOn: $settings.attentionNotificationsEnabled
                )
                Text("""
                Any program that rings the terminal bell or sends an OSC 9 \
                notification triggers the same highlight.
                """)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(20)
    }
}

#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
