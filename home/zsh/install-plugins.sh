#!/usr/bin/env bash
# home/zsh/install-plugins.sh - the two zsh plugins .zshrc sources from
# ~/.local/share/zsh-plugins (home/zsh, linked to ~/.config/zsh by
# home/install.sh). Plain git checkouts, shallow, tracking upstream main: they
# are not packaged by mise and apt/brew put them under different paths on the
# two profiles. Run by mac/setup.sh and box/bootstrap.sh step_tools, or by hand
# with `mise run zsh:plugins`. Idempotent: clone once, fast-forward after.
# Bash 3.2 compatible (the mac).

set -euo pipefail

readonly DEST="${XDG_DATA_HOME:-$HOME/.local/share}/zsh-plugins"
readonly PLUGINS="zsh-users/zsh-autosuggestions zsh-users/zsh-syntax-highlighting"

mkdir -p "$DEST"
for repo in $PLUGINS; do
  name="${repo##*/}"
  dir="$DEST/$name"
  if [[ -d $dir/.git ]]; then
    if git -C "$dir" pull -q --ff-only 2>/dev/null; then
      printf '  ok     %s\n' "$name"
    else
      printf '  WARN   %s: pull failed, keeping the current checkout\n' "$name"
    fi
  else
    git clone -q --depth 1 "https://github.com/$repo.git" "$dir"
    printf '  clone  %s\n' "$name"
  fi
done
