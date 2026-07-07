//
//  Copyright © 2026 Apparata AB. All rights reserved.
//

import AppKit
import SwiftUI

struct GeneralSettingsTab: View {

    /// zsh snippet enabling OSC 7 cwd reporting, modeled on Apple's
    /// /etc/zshrc_Apple_Terminal (byte-wise percent-encoding with
    /// LC_CTYPE=C so UTF-8 paths encode correctly).
    static let shellIntegrationSnippet = """
    # Sessions terminal: report working directory via OSC 7
    if [[ "$TERM_PROGRAM" == "Sessions" ]]; then
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

    var body: some View {
        Form {
            Section("Shell Integration") {
                Text("""
                Sessions follows your shell's working directory to open new \
                tabs in the right place and show the directory in tab \
                tooltips. Add this to your ~/.zshrc to enable it:
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
        }
        .padding(20)
    }
}

#Preview {
    GeneralSettingsTab()
        .previewEnvironment()
}
