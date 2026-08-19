#!/usr/bin/env bash
# home/install.sh <profile> - link this repository's home/ files into $HOME
# and generate the few files that are composed rather than copied.
#
# Usage: home/install.sh [--check] [--dry-run] <mac|box>
#
#   default    link and generate; idempotent, prints one line per target
#   --dry-run  print what would change, touch nothing
#   --check    report drift only; exit 1 if anything differs from the repo
#
# Everything is per file, never a whole dotdir: ~/.claude, ~/.omp/agent and
# ~/.gemini also hold runtime state (sessions, credentials, databases) that
# must never end up in this repository's working tree.
#
# Two kinds of target:
#   link      $HOME path is a symlink to a file or directory under home/
#   generated $HOME path is a regular file whose content is computed from
#             home/ (Claude settings = base + profile overlay, merged with
#             jq; the profile env file). Regenerated when the content differs.
# A regular file found where a link should be is moved to a backup directory
# under ~/.config/workbench/ before linking; the previous version of a
# generated file goes there too. Nothing is deleted.
#
# The manifest below is the ownership table in docs/01-architecture.md.
# A source that does not exist yet is reported and skipped, so this script
# is usable while files are still being moved in.

set -euo pipefail

HOME_SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK=0
DRY=0
PROFILE=""
DRIFT=0
BACKUP_DIR="$HOME/.config/workbench/backup-$(date -u +%Y%m%dT%H%M%SZ)"

usage() {
  sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2
  exit "${1:-2}"
}

# The replacement is a variable: a bare ~ would tilde-expand and \~ stays a
# literal backslash.
log() {
  local tilde='~'
  printf '  %-6s %s\n' "$1" "${2//$HOME/$tilde}"
}

# ---------------------------------------------------------------------------
# link <src-relative-to-home/> <dst-absolute>
link() {
  local src="$HOME_SRC/$1" dst="$2"
  if [[ ! -e $src ]]; then
    log SKIP "$dst (source missing: home/$1)"
    return 0
  fi
  if [[ -L $dst && "$(readlink "$dst")" == "$src" ]]; then
    log ok "$dst"
    return 0
  fi
  if ((CHECK)); then
    log DRIFT "$dst (not a link to home/$1)"
    DRIFT=1
    return 0
  fi
  if ((DRY)); then
    log would "link $dst -> home/$1"
    return 0
  fi
  if [[ -e $dst || -L $dst ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/$(basename "$dst")"
    log moved "$dst -> $BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  log link "$dst -> home/$1"
}

# generate <dst-absolute> <mode> ; expected content on stdin (redirected, not
# piped: DRIFT must be set in this shell, not in a subshell)
generate() {
  local dst="$1" mode="$2" want
  want="$(cat)"
  if [[ -f $dst && ! -L $dst && "$(cat "$dst")" == "$want" ]]; then
    log ok "$dst"
    return 0
  fi
  if ((CHECK)); then
    log DRIFT "$dst (content differs from the generated version)"
    DRIFT=1
    return 0
  fi
  if ((DRY)); then
    log would "write $dst"
    return 0
  fi
  if [[ -e $dst || -L $dst ]]; then
    mkdir -p "$BACKUP_DIR"
    cp -P "$dst" "$BACKUP_DIR/$(basename "$dst")"
    log moved "$dst -> $BACKUP_DIR/ (previous version)"
  fi
  mkdir -p "$(dirname "$dst")"
  printf '%s\n' "$want" >"$dst.tmp"
  chmod "$mode" "$dst.tmp"
  mv "$dst.tmp" "$dst"
  log write "$dst"
}

# ---------------------------------------------------------------------------
# Composed settings (D8): merge_settings <dir-under-home/> <dst-absolute>
# reads <dir>/settings.base.json and <dir>/settings.$PROFILE.json (optional).
# Objects merge recursively; the overlay wins on scalars. Two array families
# are joined instead of replaced so an overlay can add without knowing the
# base: hooks.<Event> (base hooks stay registered) and
# permissions.allow/ask/deny (deduplicated). Any other array is replaced by
# the overlay's. Strings inside arrays that start with "~/" (or are "~") get
# $HOME substituted, for path lists such as agy's trustedWorkspaces.
merge_settings() {
  local base="$HOME_SRC/$1/settings.base.json" \
    overlay="$HOME_SRC/$1/settings.$PROFILE.json" \
    dst="$2" tmp
  if [[ ! -f $base ]]; then
    log SKIP "$dst (source missing: home/$1/settings.base.json)"
    return 0
  fi
  [[ -f $overlay ]] || overlay=/dev/null
  tmp="$(mktemp)"
  jq -S -s --arg home "$HOME" '
    def joined(a; b): (a // []) + (b // []);
    .[0] as $b | (.[1] // {}) as $o
    | ($b * $o)
    | .hooks = (
        (($b.hooks // {}) | keys) + (($o.hooks // {}) | keys) | unique
        | map({key: ., value: joined($b.hooks[.]; $o.hooks[.])}) | from_entries
      )
    | if .hooks == {} then del(.hooks) else . end
    | .permissions = (
        (.permissions // {})
        | reduce ("allow","ask","deny") as $k (.;
            if ($b.permissions[$k] // $o.permissions[$k]) != null
            then .[$k] = (joined($b.permissions[$k]; $o.permissions[$k]) | unique)
            else . end)
      )
    | if .permissions == {} then del(.permissions) else . end
    | walk(if type == "array" then
             map(if type == "string" and (. == "~" or startswith("~/"))
                 then $home + .[1:] else . end)
           else . end)
  ' "$base" "$overlay" >"$tmp"
  generate "$dst" 0644 <"$tmp"
  rm -f "$tmp"
}

# The profile marker, sourced by the shell init of both profiles (bashrc's
# non-interactive part on the box, .zshenv on the mac): mise loads
# config.<MISE_ENV>.toml next to config.toml (D6).
profile_env() {
  generate "$HOME/.config/workbench/env" 0644 < <(
    printf 'export WORKBENCH_PROFILE=%s\nexport MISE_ENV=%s\n' "$PROFILE" "$PROFILE"
  )
}

# ---------------------------------------------------------------------------
manifest() {
  # shell (D5): the box reaches zsh only through bash's interactive hand-off
  link bash/interactive.sh "$HOME/.config/bash/interactive.sh"
  link zsh/.zshenv "$HOME/.zshenv"
  link zsh/.zshrc "$HOME/.zshrc"
  link zsh/regen-completions.zsh "$HOME/.config/zsh/regen-completions.zsh"
  link starship.toml "$HOME/.config/starship.toml"

  # tools (D6, D7)
  link mise/config.toml "$HOME/.config/mise/config.toml"
  link "mise/config.$PROFILE.toml" "$HOME/.config/mise/config.$PROFILE.toml"
  link git/config "$HOME/.gitconfig"
  link op-env "$HOME/.config/op-env"
  link bin/opwith "$HOME/.local/bin/opwith"

  # Claude Code (D8): settings composed, statusline linked, nothing else
  merge_settings claude "$HOME/.claude/settings.json"
  link claude/statusline.sh "$HOME/.claude/statusline.sh"

  # parallel harnesses (D12): config only, per file; agy composed like Claude
  link herdr/config.toml "$HOME/.config/herdr/config.toml"
  merge_settings agy "$HOME/.gemini/antigravity-cli/settings.json"
  link agy/statusline.sh "$HOME/.gemini/antigravity-cli/statusline.sh"
  local f
  for f in config.yml models.yml keybindings.yml lsp.json AGENTS.md RULES.md WATCHDOG.md APPEND_SYSTEM.md agents skills hooks; do
    link "omp/$f" "$HOME/.omp/agent/$f"
  done

  # editor and multiplexer: box only, the mac never had them (mise installs
  # neovim and zellij from config.box.toml)
  if [[ $PROFILE == box ]]; then
    link nvim "$HOME/.config/nvim"
    link zellij "$HOME/.config/zellij"
  fi

  profile_env
}

# ---------------------------------------------------------------------------
main() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --check) CHECK=1 ;;
      --dry-run) DRY=1 ;;
      -h | --help) usage 0 ;;
      mac | box) PROFILE="$arg" ;;
      *)
        echo "unknown argument: $arg" >&2
        usage 2
        ;;
    esac
  done
  [[ -n $PROFILE ]] || {
    echo "profile required: mac or box" >&2
    usage 2
  }
  command -v jq >/dev/null || {
    echo "jq is required" >&2
    exit 1
  }

  local mode="install"
  ((CHECK)) && mode="check"
  ((DRY)) && mode="dry-run"
  echo "home/install.sh: profile=$PROFILE mode=$mode source=$HOME_SRC"
  manifest
  if ((CHECK)); then
    if ((DRIFT)); then
      echo "drift detected"
      exit 1
    fi
    echo "no drift"
  fi
}

main "$@"
