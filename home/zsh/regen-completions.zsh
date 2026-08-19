#!/usr/bin/env zsh
# =============================================================================
# Pre-generate zsh completion files.
# =============================================================================
# Run by `mise run completions:regen`, and once during `docker build` so the
# image ships with them.
#
# Why this exists: the previous .zshrc ran `source <(kubectl completion zsh)`
# and five more like it on every single shell start. That is one fork + one
# process spawn per tool, per terminal, forever. Writing them to a directory on
# $fpath instead means zsh loads each one lazily, only when you actually press
# TAB on that command.
#
# Safe to run repeatedly; missing tools are skipped.
# =============================================================================

set -euo pipefail

readonly OUT="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/completions"
mkdir -p "$OUT"

# tool -> command that prints a zsh completion script on stdout
typeset -A gens=(
    kubectl   "kubectl completion zsh"
    helm      "helm completion zsh"
    helmfile  "helmfile completion zsh"
    talosctl  "talosctl completion zsh"
    argocd    "argocd completion zsh"
    cilium    "cilium completion zsh"
    k9s       "k9s completion zsh"
    gh        "gh completion -s zsh"
    op        "op completion zsh"
    mise      "mise completion zsh"
    starship  "starship completions zsh"
    omp       "omp completions zsh"
    herdr     "herdr completion zsh"
    zoxide    "zoxide init zsh --no-cmd"
    usql      "usql --completion-script-zsh"
)

for tool script in ${(kv)gens}; do
    if (( ! $+commands[$tool] )); then
        print "skip  $tool (not installed)"
        continue
    fi
    if ${=script} > "$OUT/_$tool.tmp" 2>/dev/null && [[ -s "$OUT/_$tool.tmp" ]]; then
        mv "$OUT/_$tool.tmp" "$OUT/_$tool"
        print "ok    $tool"
    else
        rm -f "$OUT/_$tool.tmp"
        print "fail  $tool (generator returned nothing)"
    fi
done

# --- Init snippets -----------------------------------------------------------
# Same idea as above, for tools whose shell hook is not a completion file but
# an init script that would otherwise be `source <(tool --zsh)` on every
# start. Written next to the completions and sourced by .zshrc if present.
readonly INIT="${XDG_DATA_HOME:-$HOME/.local/share}/zsh/init"
mkdir -p "$INIT"

typeset -A inits=(
    fzf       "fzf --zsh"
)

for tool script in ${(kv)inits}; do
    if (( ! $+commands[$tool] )); then
        print "skip  $tool init (not installed)"
        continue
    fi
    if ${=script} > "$INIT/$tool.zsh.tmp" 2>/dev/null && [[ -s "$INIT/$tool.zsh.tmp" ]]; then
        mv "$INIT/$tool.zsh.tmp" "$INIT/$tool.zsh"
        print "ok    $tool init"
    else
        rm -f "$INIT/$tool.zsh.tmp"
        print "fail  $tool init (generator returned nothing)"
    fi
done

# The completion cache is invalidated by removing the compdump; the next
# interactive shell rebuilds it.
rm -f "${XDG_CACHE_HOME:-$HOME/.cache}/zsh/zcompdump"

print "\ncompletions written to $OUT, init snippets to $INIT"
