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
# Overridable so a caller (mac/setup.sh) and this script share one backup dir.
BACKUP_DIR="${BACKUP_DIR:-$HOME/.config/workbench/backup-$(date -u +%Y%m%dT%H%M%SZ)}"

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
# link <path-under-home/> <dst>
link() { link_path "$HOME_SRC/$1" "home/$1" "$2"; }

link_path() {
  local src="$1" label="$2" dst="$3"
  if [[ ! -e $src ]]; then
    log SKIP "$dst (source missing: $label)"
    return 0
  fi
  if [[ -L $dst && "$(readlink "$dst")" == "$src" ]]; then
    log ok "$dst"
    return 0
  fi
  if ((CHECK)); then
    log DRIFT "$dst (not a link to $label)"
    DRIFT=1
    return 0
  fi
  if ((DRY)); then
    log would "link $dst -> $label"
    return 0
  fi
  if [[ -e $dst || -L $dst ]]; then
    mkdir -p "$BACKUP_DIR"
    mv "$dst" "$BACKUP_DIR/$(basename "$dst")"
    log moved "$dst -> $BACKUP_DIR/"
  fi
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  log link "$dst -> $label"
}

# generate <dst-absolute> <mode> ; expected content on stdin (redirected, not
# piped: DRIFT must be set in this shell, not in a subshell)
# Structured targets compare by MEANING, not bytes: agy rewrites its
# settings.json in its own key order on every run and omp reserialises its
# config.yml without comments, and neither reformatting is a change. Only a
# different key or value is drift. Without a parser (a stripped-down machine,
# or the tool that provides it not installed yet) the comparison falls back to
# bytes, which over-reports drift rather than under-reporting it.
same_content() {
  local dst="$1" want="$2"
  [[ -f $dst && ! -L $dst ]] || return 1
  if [[ $dst == *.json ]] && command -v jq >/dev/null 2>&1; then
    [[ "$(jq -S . "$dst" 2>/dev/null)" == "$(printf '%s\n' "$want" | jq -S . 2>/dev/null)" ]]
  elif [[ $dst == *.yml || $dst == *.yaml ]] &&
    command -v yq >/dev/null 2>&1 && command -v jq >/dev/null 2>&1; then
    local have_yaml want_yaml
    have_yaml="$(yq -o=json "$dst" 2>/dev/null | jq -S . 2>/dev/null)"
    want_yaml="$(printf '%s\n' "$want" | yq -o=json 2>/dev/null | jq -S . 2>/dev/null)"
    [[ -n $have_yaml && "$have_yaml" == "$want_yaml" ]]
  else
    [[ "$(cat "$dst")" == "$want" ]]
  fi
}

generate() {
  local dst="$1" mode="$2" want
  want="$(cat)"
  if same_content "$dst" "$want"; then
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
# permissions.allow/ask/deny, both deduplicated so a hook or rule listed in
# base and overlay fires once. Any other array is replaced by the overlay's.
# Strings inside arrays that start with "~/" (or are "~") get $HOME
# substituted, for path lists such as agy's trustedWorkspaces.
#
# Optional third argument: comma-separated top-level keys the TOOL owns after
# first install ("seed keys"). The repo supplies their initial value; once the
# target exists, the tool's current value is carried over instead, so a model
# picked in the tool's UI or a workspace trusted interactively is neither
# reported as drift nor reset by the next provision. Everything else stays
# repo-owned and is still compared and rewritten.
merge_settings() {
  local base="$HOME_SRC/$1/settings.base.json" \
    overlay="$HOME_SRC/$1/settings.$PROFILE.json" \
    dst="$2" seed="${3:-}" tmp have
  if [[ ! -f $base ]]; then
    log SKIP "$dst (source missing: home/$1/settings.base.json)"
    return 0
  fi
  [[ -f $overlay ]] || overlay=/dev/null
  have='{}'
  if [[ -n $seed && -f $dst && ! -L $dst ]]; then
    have="$(jq -c . "$dst" 2>/dev/null || printf '{}')"
  fi
  tmp="$(mktemp)"
  jq -S -s --arg home "$HOME" --arg seed "$seed" --argjson have "$have" '
    def joined(a; b): (a // []) + (b // []);
    .[0] as $b | (.[1] // {}) as $o
    | ($b * $o)
    | .hooks = (
        (($b.hooks // {}) | keys) + (($o.hooks // {}) | keys) | unique
        | map({key: ., value: (joined($b.hooks[.]; $o.hooks[.]) | unique)}) | from_entries
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
    | reduce (($seed | split(",")) | map(select(. != ""))[]) as $k (.;
        if $have | has($k) then .[$k] = $have[$k] else . end)
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
  link zsh/install-plugins.sh "$HOME/.config/zsh/install-plugins.sh"
  link starship.toml "$HOME/.config/starship.toml"

  # tools (D6, D7)
  link mise/config.toml "$HOME/.config/mise/config.toml"
  link "mise/config.$PROFILE.toml" "$HOME/.config/mise/config.$PROFILE.toml"
  link git/config "$HOME/.gitconfig"
  link git/allowed_signers "$HOME/.config/git/allowed_signers"
  link op-env "$HOME/.config/op-env"
  link bin/opwith "$HOME/.local/bin/opwith"

  # Claude Code (D8): settings composed, statusline linked, nothing else
  merge_settings claude "$HOME/.claude/settings.json"
  link claude/statusline.sh "$HOME/.claude/statusline.sh"

  # Claude behaviour (D9): global instructions, subagents, the one global
  # skill and the boundary gate, all under home/claude/ next to the settings.
  # ~/.claude/agents is linked as a directory (nothing else writes there);
  # skills and hooks per entry, because other installers own siblings in
  # those directories. omp-fleet's fallback config sits at
  # ~/.claude/omp-delegate.yml, where omp-run.sh looks for it.
  link claude/CLAUDE.md "$HOME/.claude/CLAUDE.md"
  link claude/agents "$HOME/.claude/agents"
  link claude/skills/omp-fleet "$HOME/.claude/skills/omp-fleet"
  link claude/skills/omp-fleet/omp-delegate.yml "$HOME/.claude/omp-delegate.yml"
  link claude/hooks/boundary-gate.sh "$HOME/.claude/hooks/boundary-gate.sh"

  # parallel harnesses (D12): config only, per file; agy composed like Claude
  link herdr/config.toml "$HOME/.config/herdr/config.toml"
  # agy stores model under its display name ("Gemini 3.7 Flash (High)", not an
  # id; an id is accepted once, then rewritten with a warning on first run) and
  # appends what the operator trusts in-session to trustedWorkspaces; both are
  # seed keys, see merge_settings.
  merge_settings agy "$HOME/.gemini/antigravity-cli/settings.json" model,trustedWorkspaces
  link agy/statusline.sh "$HOME/.gemini/antigravity-cli/statusline.sh"
  # config.yml is generated, not linked. omp writes to
  # ~/.omp/agent/config.yml itself: `omp config set`, `omp config reset`, the
  # in-session /settings panel, and - the case that actually bit - a schema
  # migration on upgrade, which rewrites the whole file (omp 17 replaced
  # advisor.subagents with task.agentAdvisor that way). Through a symlink every
  # one of those writes lands in a tracked file and strips its comments. As a
  # generated file they are drift that the next install.sh reverts, and `--check`
  # names them. Same reasoning as agy above, one file format down.
  generate "$HOME/.omp/agent/config.yml" 0644 <"$HOME_SRC/omp/config.yml"
  local f
  for f in models.yml keybindings.yml lsp.json AGENTS.md RULES.md WATCHDOG.md APPEND_SYSTEM.md agents skills hooks; do
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
# The boundary gate is the one link whose absence fails silently: an agent
# simply never sees a block. So the link is not the deliverable; the gate must
# be registered (settings.base.json carries the PreToolUse entry) and must
# behave. Fed the payload shape Claude Code sends, against the source file, so
# it runs in every mode.
verify_gate() {
  local gate="$HOME_SRC/claude/hooks/boundary-gate.sh" failed=0
  [[ -f $gate ]] || return 0
  if grep -q 'boundary-gate.sh' "$HOME_SRC/claude/settings.base.json"; then
    log ok "boundary-gate registered in home/claude/settings.base.json"
  else
    log FAIL "boundary-gate not registered in home/claude/settings.base.json"
    failed=1
  fi
  local label cmd want got
  while IFS='|' read -r label cmd want; do
    got=0
    printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$cmd" |
      bash "$gate" >/dev/null 2>&1 || got=$?
    if [[ $got == "$want" ]]; then
      log ok "gate $label (exit $got)"
    else
      log FAIL "gate $label: expected exit $want, got $got"
      failed=1
    fi
  done <<'EOT'
blocks git push --force|git push --force origin main|2
allows git push|git push origin main|0
allows git status|git status|0
EOT
  if ((failed)); then
    echo "boundary-gate self-check failed; the gate may be open" >&2
    exit 1
  fi
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
  verify_gate
  if ((CHECK)); then
    if ((DRIFT)); then
      echo "drift detected"
      exit 1
    fi
    echo "no drift"
  fi
}

main "$@"
