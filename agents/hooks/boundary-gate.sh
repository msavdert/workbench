#!/usr/bin/env bash
# PreToolUse gate for actions that LEAVE the sandbox.
#
# The sandbox makes local damage reversible: a reimage undoes rm -rf, a bad
# build, a wrecked working tree. That is why the permission prompts are
# deliberately disabled (skipDangerousModePermissionPrompt: true) — prompting
# on reversible actions is pure friction.
#
# This gate covers only what the sandbox does NOT contain: actions performed
# with credentials that are valid outside it. A reimage does not undo a
# force-push over main or a secret written into a tracked file.
#
# Exit 0 = allow. Exit 2 = block; stderr is fed back to the model, which is
# expected to ask the owner instead of routing around the gate.
#
# Escape hatch: the owner runs the command themselves (`! git push ...`).
# There is deliberately no environment variable override — an override the
# agent can set is not a gate.

set -uo pipefail

payload="$(cat)"

field() {
    if command -v jq >/dev/null 2>&1; then
        printf '%s' "$payload" | jq -r "$1 // empty" 2>/dev/null
    fi
}

tool="$(field '.tool_name')"

block() {
    printf 'BLOCKED by workbench boundary-gate: %s\n\n%s\n' "$1" "$2" >&2
    exit 2
}

# --- Crossing 1: a push that destroys remote history ------------------------
# A plain push is allowed: it only ever ADDS commits, and a bad one is undone
# by another push. The gated forms delete or overwrite refs on the remote, and
# no reimage brings those back — the remote is outside the sandbox.
if [[ -z "$tool" || "$tool" == "Bash" ]]; then
    cmd="$(field '.tool_input.command')"
    [[ -z "$cmd" ]] && cmd="$payload"

    # `git ... push` with no quote or command separator in between, so global
    # flags (`git -c a=b push`) are caught while a commit message that merely
    # mentions the word is not.
    if printf '%s' "$cmd" | grep -Eq "(^|[;&|[:space:]])git[^;&|'\"]*[[:space:]]push($|[[:space:]])"; then
        # Only the arguments of this push, not whatever is chained after it.
        args="${cmd#* push}"
        args="${args%%[;&|]*}"

        # --force-with-lease refuses when the remote moved, so it cannot
        # silently destroy work someone else pushed. It stays allowed.
        lease=0
        printf '%s' "$args" | grep -q -- '--force-with-lease' && lease=1

        why=""
        [[ $lease -eq 0 ]] && printf '%s' "$args" | grep -Eq -- '(^|[[:space:]])(--force|-f)($|[[:space:]=])' \
            && why="--force overwrites remote history"
        printf '%s' "$args" | grep -Eq -- '(^|[[:space:]])(--delete|-d)($|[[:space:]=])' \
            && why="--delete removes a remote branch"
        printf '%s' "$args" | grep -Eq -- '(^|[[:space:]])--mirror($|[[:space:]=])' \
            && why="--mirror overwrites every remote ref at once"
        printf '%s' "$args" | grep -Eq '(^|[[:space:]])\+[^[:space:]]*:' \
            && why="a + refspec is a force push"
        printf '%s' "$args" | grep -Eq '(^|[[:space:]]):[^[:space:]]+' \
            && why="a :ref refspec deletes a remote ref"

        [[ -n "$why" ]] && block "destructive push ($why)" \
"Plain pushes are allowed here; this one deletes or overwrites refs on a real
remote, which no reimage undoes. Stop and ask the owner. If they want it, let
them run it themselves with a leading '!', or use --force-with-lease."
    fi
fi

# --- Crossing 2: a literal credential heading for disk -----------------------
# Rejected because credentials resolve from 1Password op:// references. A
# literal value in a file is a leak the moment it is committed or pushed, and
# rotating it is work the sandbox cannot undo.
if [[ -z "$tool" || "$tool" == "Write" || "$tool" == "Edit" || "$tool" == "NotebookEdit" ]]; then
    content="$(field '.tool_input.content')
$(field '.tool_input.new_string')"
    [[ -z "${content//[[:space:]]/}" ]] && content="$payload"

    if printf '%s' "$content" | grep -Eq \
        'ghp_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|sk-ant-[A-Za-z0-9_-]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]{10,}|-----BEGIN [A-Z ]*PRIVATE KEY-----'; then
        block "a literal credential is being written to disk" \
"Credentials resolve from 1Password op:// references, injected per command.
Replace the literal with an op:// reference. If this is a redacted sample,
mangle it so it no longer matches a real key format."
    fi
fi

exit 0
