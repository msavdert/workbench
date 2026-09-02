#!/usr/bin/env bash
# PreToolUse gate for reads that would flood the context.
#
# The operator's standing rule is "read a line range, not a whole file;
# anything over ~50 lines goes to a subagent". Stated in CLAUDE.md it held
# for a few turns per session and then decayed, so the operator repeated it
# every session by hand. This gate is the mechanical form of that rule: a
# Read without a limit, or a bare `cat FILE` in Bash, on a file longer than
# MAX_LINES is refused with the instruction the operator used to type.
#
# Exit 0 = allow. Exit 2 = block; stderr goes back to the model.
#
# Non-goal: resisting a model that works around it (`limit: 100000`,
# `cat a b`, `sed -n 1,9999p`). The match is textual and catches the plain,
# accidental case; the fix for a determined agent is its instructions.
# Non-text files (images, PDFs, notebooks) pass: Read renders them, and a
# line count means nothing there.

set -uo pipefail

MAX_LINES=200

payload="$(cat)"

field() {
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
  fi
}

block() {
  printf 'BLOCKED by workbench read-gate: %s\n\n%s\n' "$1" "$2" >&2
  exit 2
}

# too_long FILE [OFFSET]: true when the lines from OFFSET to the end exceed
# MAX_LINES; an offset without a limit still reads to the end of the file.
# bash 3.2: no ${x,,}, so the extension goes through tr.
too_long() {
  local f="$1" from="${2:-0}" n ext
  f="${f/#\~/$HOME}"
  [[ -f $f ]] || return 1
  ext="$(printf '%s' "${f##*.}" | tr '[:upper:]' '[:lower:]')"
  case "$ext" in
    png | jpg | jpeg | gif | webp | svg | pdf | ipynb) return 1 ;;
  esac
  n="$(wc -l <"$f" 2>/dev/null || echo 0)"
  [[ $from =~ ^[0-9]+$ ]] || from=0
  [[ $((n - from)) -gt $MAX_LINES ]]
}

tool="$(field '.tool_name')"

case "$tool" in
  Read)
    file="$(field '.tool_input.file_path')"
    limit="$(field '.tool_input.limit')"
    offset="$(field '.tool_input.offset')"
    [[ -n $file && -z $limit ]] || exit 0
    if too_long "$file" "$offset"; then
      block "$file has more than $MAX_LINES lines from the start of the read and no limit was given" \
        "Locate the range with grep or an LSP lookup and Read it with offset and limit, or send the whole-file read to a subagent (Explore) and keep only its findings. Every line read here is re-billed on every later turn."
    fi
    ;;
  Bash)
    cmd="$(field '.tool_input.command')"
    # bare `cat FILE`: one argument, bare or in one pair of quotes (a quoted
    # path may hold spaces), no pipe, no redirection, no second command
    if [[ $cmd =~ ^[[:space:]]*cat[[:space:]]+(\"([^\"]+)\"|\'([^\']+)\'|([^[:space:]\"\'|\;\&\>\<]+))[[:space:]]*$ ]]; then
      file="${BASH_REMATCH[2]}${BASH_REMATCH[3]}${BASH_REMATCH[4]}"
      if too_long "$file"; then
        block "cat $file would print more than $MAX_LINES lines" \
          "Print a range (sed -n 'a,bp') or grep for what you need, or send the read to a subagent (Explore). Every line printed here is re-billed on every later turn."
      fi
    fi
    ;;
esac
exit 0
