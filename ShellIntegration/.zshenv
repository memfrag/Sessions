# Sessions terminal: shell integration bootstrap.
#
# The session server points ZDOTDIR here so this file runs first; it
# restores the user's real ZDOTDIR, chains to their own .zshenv, and
# loads the Sessions integration for interactive shells.

if [[ -n "$SESSIONS_ORIG_ZDOTDIR" ]]; then
    export ZDOTDIR="$SESSIONS_ORIG_ZDOTDIR"
    unset SESSIONS_ORIG_ZDOTDIR
else
    unset ZDOTDIR
fi

if [[ -f "${ZDOTDIR:-$HOME}/.zshenv" ]]; then
    builtin source "${ZDOTDIR:-$HOME}/.zshenv"
fi

if [[ -o interactive && -n "$SESSIONS_INTEGRATION_DIR" ]] \
    && [[ -f "$SESSIONS_INTEGRATION_DIR/sessions-integration.zsh" ]]; then
    builtin source "$SESSIONS_INTEGRATION_DIR/sessions-integration.zsh"
fi
