//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

struct GeneralSettingsTab: View {

    /// Claude Code hooks that report the Claude lifecycle via OSC 9
    /// (`claude:working` / `claude:input` / `claude:done` → tab badges).
    /// Hooks run detached from the controlling terminal, so this writes
    /// to the terminal device by the path captured in SESSIONS_TTY (set
    /// by the shell integration), falling back to /dev/tty.
    static let claudeCodeHookSnippet = """
    {
      "hooks": {
        "UserPromptSubmit": [
          { "hooks": [ { "type": "command",
            "command": "printf '\\\\033]9;claude:working\\\\007' > \\"${SESSIONS_TTY:-/dev/tty}\\"" } ] }
        ],
        "Notification": [
          { "hooks": [ { "type": "command",
            "command": "printf '\\\\033]9;claude:input\\\\007' > \\"${SESSIONS_TTY:-/dev/tty}\\"" } ] }
        ],
        "Stop": [
          { "hooks": [ { "type": "command",
            "command": "printf '\\\\033]9;claude:done\\\\007' > \\"${SESSIONS_TTY:-/dev/tty}\\"" } ] }
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
        Form {
            shellIntegrationSection
            claudeCodeSection
        }
        .padding(20)
    }

    private var shellIntegrationSection: some View {
        Section("Shell Integration") {
            Text("""
            Sessions follows your shell's working directory to open new \
            tabs in the right place and show the directory in tab \
            tooltips. This is set up automatically for zsh. For other \
            shells, add the equivalent of this to your shell config:
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            snippetBox(Self.shellIntegrationSnippet, maxHeight: 150)
            Button("Copy Snippet") {
                copyToPasteboard(Self.shellIntegrationSnippet)
            }
        }
    }

    private var claudeCodeSection: some View {
        @Bindable var settings = settings
        return Section("Claude Code Integration") {
            Text("""
            Sessions shows each tab's Claude state: an hourglass while \
            Claude is working, an orange bell when it needs your input, \
            and a green checkmark when it is done. In zsh this works \
            automatically — the `claude` command is wrapped to load the \
            hooks. For other shells, merge these hooks into \
            ~/.claude/settings.json:
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
            snippetBox(Self.claudeCodeHookSnippet, maxHeight: 130)
            Button("Copy Hook") {
                copyToPasteboard(Self.claudeCodeHookSnippet)
            }
            Toggle(
                "Also show Notification Center alerts",
                isOn: $settings.attentionNotificationsEnabled
            )
            Toggle(
                "Play a sound",
                isOn: $settings.attentionNotificationSoundEnabled
            )
            .disabled(!settings.attentionNotificationsEnabled)
            Text("""
            Any program that rings the terminal bell or sends an OSC 9 \
            notification triggers the same highlight.
            """)
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    /// A scrollable, selectable monospaced snippet box.
    private func snippetBox(_ text: String, maxHeight: CGFloat) -> some View {
        ScrollView(.horizontal) {
            Text(text)
                .font(.caption.monospaced())
                .textSelection(.enabled)
                .padding(8)
        }
        .frame(maxHeight: maxHeight)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.primary.opacity(0.05))
        )
    }

    private func copyToPasteboard(_ string: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(string, forType: .string)
    }
}

#if DEBUG
#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
#endif
