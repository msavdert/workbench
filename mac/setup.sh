#!/usr/bin/env bash
# mac/setup.sh - provision the thin client (the laptop).
#
# Homebrew for GUI applications and host daemons (mac/Brewfile), mise from
# the standalone installer for CLI tools (home/mise/config.toml +
# config.mac.toml), then the links: mac-only files from mac/ (ssh, ghostty)
# and everything shared through home/install.sh mac. Idempotent; a second
# run changes nothing.
#
# Usage:
#   mac/setup.sh               full run
#   mac/setup.sh --links-only  only refresh links (what `mise run mac:sync` does)
#   DRY_RUN=1 mac/setup.sh     show what would happen
#   CLEANUP=1 mac/setup.sh     also uninstall brew packages not in the Brewfile

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_DIR
readonly DRY_RUN="${DRY_RUN:-}"
BACKUP_DIR="$HOME/.config/workbench/backup-$(date -u +%Y%m%dT%H%M%SZ)"
readonly BACKUP_DIR
export BACKUP_DIR # home/install.sh honours it: one backup dir per run

info() { printf '  ok     %s\n' "$*"; }
warn() { printf '  WARN   %s\n' "$*"; }
step() { printf '\n==> %s\n' "$*"; }
die() {
  printf 'mac/setup.sh: %s\n' "$*" >&2
  exit 1
}
run() {
  if [[ -n $DRY_RUN ]]; then
    printf '  would  %s\n' "$*"
  else
    "$@"
  fi
}

require_macos() {
  [[ "$(uname -s)" == "Darwin" ]] || die "macOS only; the box is provisioned by box/bootstrap.sh"
}

install_homebrew() {
  step "Homebrew"
  if command -v brew >/dev/null 2>&1; then
    info "already installed ($(brew --version | head -1))"
    return
  fi
  [[ -n $DRY_RUN ]] && {
    warn "would install Homebrew"
    return
  }
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
  # Apple Silicon puts brew outside the default PATH.
  [[ -x /opt/homebrew/bin/brew ]] && eval "$(/opt/homebrew/bin/brew shellenv)"
}

apply_brewfile() {
  step "Brewfile"
  command -v brew >/dev/null 2>&1 || {
    warn "brew missing, skipping"
    return
  }
  # `brew bundle cleanup` without --force only prints what it would remove;
  # CLEANUP=1 applies it. That is the declarative point of the Brewfile.
  if [[ -n $DRY_RUN ]]; then
    brew bundle check --file="$REPO_DIR/mac/Brewfile" --verbose || true
    brew bundle cleanup --file="$REPO_DIR/mac/Brewfile" || true
    return
  fi
  brew bundle install --file="$REPO_DIR/mac/Brewfile"
  if [[ "${CLEANUP:-}" == "1" ]]; then
    brew bundle cleanup --file="$REPO_DIR/mac/Brewfile" --force
    info "removed packages not present in the Brewfile"
  else
    brew bundle cleanup --file="$REPO_DIR/mac/Brewfile" || true
    warn "anything listed above would be REMOVED; re-run with CLEANUP=1 to apply"
  fi
}

install_mise() {
  step "mise"
  # Standalone installer, not brew: no second brew-managed copy shadowing
  # ~/.local/bin/mise.
  if command -v mise >/dev/null 2>&1; then
    info "already installed ($(mise --version))"
    return
  fi
  [[ -n $DRY_RUN ]] && {
    warn "would install mise from https://mise.run"
    return
  }
  curl -fsSL https://mise.run | sh
  export PATH="$HOME/.local/bin:$PATH"
}

# link <src-under-mac/> <dst>: same semantics as home/install.sh (a file in
# the way is moved to the backup dir, never deleted).
link() {
  local src="$REPO_DIR/mac/$1" dst="$2"
  if [[ -L $dst && "$(readlink "$dst")" == "$src" ]]; then
    info "$dst"
    return
  fi
  if [[ -n $DRY_RUN ]]; then
    printf '  would  link %s -> mac/%s\n' "$dst" "$1"
    return
  fi
  if [[ -e $dst || -L $dst ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/$(basename "$dst")"
    printf '  moved  %s -> %s/\n' "$dst" "$BACKUP_DIR"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  printf '  link   %s -> mac/%s\n' "$dst" "$1"
}

link_mac() {
  step "Links: mac/ (ssh, ghostty)"
  run mkdir -p "$HOME/.ssh/sockets"
  run chmod 700 "$HOME/.ssh"
  link ssh/config "$HOME/.ssh/config"
  link ssh/config.macos "$HOME/.ssh/config.macos"
  link ghostty/config "${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
}

link_home() {
  step "Links: home/ (home/install.sh mac)"
  if [[ -n $DRY_RUN ]]; then
    "$REPO_DIR/home/install.sh" --dry-run mac
  else
    "$REPO_DIR/home/install.sh" mac
  fi
}

install_mise_tools() {
  step "CLI tools (home/mise/config.toml + config.mac.toml)"
  if ! command -v mise >/dev/null 2>&1; then
    warn "mise not on PATH yet - open a new shell and re-run"
    return
  fi
  # MISE_ENV=mac comes from ~/.config/workbench/env, written by link_home;
  # export it here too because this shell predates that file.
  export MISE_ENV=mac
  run mise install -y
  run mise prune --yes
}

regen_completions() {
  step "zsh completions and init snippets"
  if command -v zsh >/dev/null 2>&1; then
    run zsh "$REPO_DIR/home/zsh/regen-completions.zsh"
  fi
}

check_1password_agent() {
  step "1Password SSH agent"
  local sock="$HOME/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
  if [[ -S $sock ]]; then
    info "agent socket is live; mac/ssh/config.macos points IdentityAgent at it"
  else
    warn "agent socket not found: 1Password -> Settings -> Developer -> 'Use the SSH agent'"
    warn "until then ssh falls back to on-disk keys"
  fi
}

summary() {
  cat <<'TXT'

The mac is provisioned.
  exec zsh              reload the shell
  op signin             unlock 1Password CLI
  make ssh              tmux session on the box (needs agent-vm-ssh in ~/.ssh/config.local)
  mise run mac:sync     pull this repository and refresh the links
TXT
}

main() {
  require_macos
  if [[ "${1:-}" == "--links-only" ]]; then
    link_mac
    link_home
    return
  fi
  install_homebrew
  apply_brewfile
  install_mise
  link_mac
  link_home
  install_mise_tools
  regen_completions
  check_1password_agent
  summary
}

main "$@"
