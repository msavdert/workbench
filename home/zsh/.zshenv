# =============================================================================
# .zshenv - sourced by EVERY zsh (interactive, non-interactive, scripts)
# =============================================================================
# Only things that must exist for `ssh box 'some-command'` and for editors
# that spawn a non-login shell. Keep it fast: no subprocesses, no network.
# Interactive-only setup belongs in .zshrc.
#
# On the box zsh is only ever reached through bash's interactive hand-off
# (home/bash/interactive.sh, D5): agent shells are bash and never see this.
# =============================================================================

# --- Profile ---
# Written by home/install.sh <profile>: WORKBENCH_PROFILE and MISE_ENV, so
# mise loads config.<profile>.toml next to the shared config.toml (D6).
[[ -r "${XDG_CONFIG_HOME:-$HOME/.config}/workbench/env" ]] \
    && source "${XDG_CONFIG_HOME:-$HOME/.config}/workbench/env"

# --- Locale ---
# Set LANG only, and only when the environment has not already chosen one.
# Exporting LC_ALL unconditionally overrides every per-category setting and is
# almost never what you want.
: "${LANG:=en_US.UTF-8}"
export LANG

# --- PATH ---
# mise shims make tools resolvable in NON-interactive shells (scripts, ssh
# one-liners, editors). Interactive shells additionally run `mise activate`
# in .zshrc, which shadows the shims with the faster direct paths.
typeset -U path                                   # de-duplicate automatically
path=("$HOME/.local/bin" "$HOME/.local/share/mise/shims" $path)
export PATH

# --- Defaults ---
if (( $+commands[nvim] )); then
    export EDITOR="nvim"
    export VISUAL="nvim"
elif (( $+commands[vim] )); then
    export EDITOR="vim"
    export VISUAL="vim"
else
    export EDITOR="vi"
    export VISUAL="vi"
fi
export PAGER="less"
export LESS="-FRX"

# --- XDG & Tool Configs ---
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
# CLAUDE_CONFIG_DIR is deliberately NOT set: it was a devbox Docker-volume
# workaround and it moves ~/.claude.json to ~/.claude/.claude.json, so a claude
# started from zsh (a human TTY) and one started from bash (ssh, Remote
# Control) would see different accounts and project state. One identity per
# machine: Claude Code's defaults.

