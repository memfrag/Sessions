# Sessions terminal: automatic zsh integration.
#
# - Reports the working directory via OSC 7 (cwd inheritance for new
#   tabs, tab tooltips). Same technique as /etc/zshrc_Apple_Terminal.
# - Wraps the `claude` command so Claude Code loads the Sessions
#   attention hooks (tab/workspace highlight and optional notifications
#   when Claude needs input) without editing ~/.claude/settings.json.

if [[ "$TERM_PROGRAM" == "Sessions" ]]; then

    # Capture this shell's terminal device path so tools whose subprocesses
    # are detached from the controlling terminal (e.g. Claude Code hooks,
    # which cannot use /dev/tty) can still write escape sequences back to
    # the terminal by explicit path.
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
        printf '\e]7;%s\a' "file://$HOST$url_path"
    }

    autoload -Uz add-zsh-hook
    add-zsh-hook precmd __sessions_update_cwd

    if [[ -n "$SESSIONS_CLAUDE_HOOKS" && -f "$SESSIONS_CLAUDE_HOOKS" ]]; then
        claude() {
            command claude --settings "$SESSIONS_CLAUDE_HOOKS" "$@"
        }
    fi
fi
