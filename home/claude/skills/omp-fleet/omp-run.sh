#!/usr/bin/env bash
# Safe launcher for delegated omp runs.
#
# Exists because of a real incident on 2026-08-14: a delegated research run was
# given the default tool set, used the `task` tool to fan out nine parallel
# `omp fetch` subagents, and those subagents were spawned by omp's persistent
# worker daemon rather than by the run itself. When the parent died on an HTTP
# 429, the nine children kept running for another 25 minutes and drained the
# daily quota on both providers. Neither --max-time nor a process-group kill
# would have stopped them, because they were never in the parent's process
# group.
#
# Three defences, in order of importance:
#   1. --tools allowlist with no `task`. The fan-out cannot happen at all.
#      It also removes bash/python/browser, which is what stopped earlier runs
#      from writing their own DuckDuckGo scrapers instead of using web_search.
#   2. Orphan reaping. PIDs of `omp fetch` processes are snapshotted before the
#      run; anything new at exit is killed, whoever its parent is.
#   3. A quota gate. Refuses to start against an exhausted pool instead of
#      burning a slot to discover it.
#
# Usage:
#   tools/omp-run.sh <topic> <prompt-file> [model] [max-seconds]
#   tools/omp-run.sh reap              # kill every stray omp agent, now
#   tools/omp-run.sh status            # what is running and what quota is left

set -euo pipefail

# This copy lives in ~/.claude/skills/ and is shared by every project, so the
# project root is the current directory, not the script's own location.
# Override with OMP_PROJECT_ROOT when launching from somewhere else.
REPO="${OMP_PROJECT_ROOT:-$PWD}"

# Project config wins; the global one is the fallback. The config exists only
# to disable omp's advisor runtime, so the global copy is fine for most work.
if [[ -n "${OMP_CONFIG:-}" ]]; then
  CONFIG="$OMP_CONFIG"
elif [[ -f "$REPO/.claude/omp-delegate.yml" ]]; then
  CONFIG="$REPO/.claude/omp-delegate.yml"
else
  CONFIG="$HOME/.claude/omp-delegate.yml"
fi

# No `task`: no subagent fan-out. No bash/python/browser: no self-written
# scrapers. A research delegate needs exactly these three.
TOOLS="read,write,web_search"

# Refuse to start a run against a pool this close to empty.
QUOTA_CEILING=90

agent_pids() {
  pgrep -f "omp fetch" 2>/dev/null || true
  pgrep -f "omp-python-runner" 2>/dev/null || true
}

quota_pct() {
  # $1 is a substring of the usage line, e.g. "Usage (Google)".
  NO_COLOR=1 timeout 60 omp usage 2>/dev/null \
    | sed 's/\x1b\[[0-9;]*m//g' \
    | grep -F -- "$1" \
    | grep -oE '[0-9]+(\.[0-9]+)?% used' \
    | head -1 \
    | grep -oE '^[0-9]+(\.[0-9]+)?' \
    || true
}

reap() {
  local before="$1"
  local killed=0
  for pid in $(agent_pids); do
    if ! grep -qx "$pid" <<<"$before"; then
      kill -TERM "$pid" 2>/dev/null && killed=$((killed + 1))
    fi
  done
  if [ "$killed" -gt 0 ]; then
    sleep 3
    for pid in $(agent_pids); do
      grep -qx "$pid" <<<"$before" || kill -KILL "$pid" 2>/dev/null || true
    done
    echo "reaped $killed stray omp agent(s)" >&2
  fi
}

case "${1:-}" in
  reap)
    for pid in $(agent_pids); do kill -TERM "$pid" 2>/dev/null || true; done
    sleep 3
    for pid in $(agent_pids); do kill -KILL "$pid" 2>/dev/null || true; done
    pkill -f "__omp_worker_daemon_broker" 2>/dev/null || true
    echo "all omp agents and the worker daemon killed"
    exit 0
    ;;
  status)
    echo "--- running omp agents ---"
    ps -eo pid,etime,args 2>/dev/null \
      | grep -E "omp fetch|omp_worker_daemon|omp-python-runner" \
      | grep -v grep | cut -c1-110 || echo "none"
    echo "--- quota ---"
    NO_COLOR=1 timeout 60 omp usage 2>&1 | sed 's/\x1b\[[0-9;]*m//g'
    exit 0
    ;;
esac

TOPIC="${1:?usage: omp-run.sh <topic> <prompt-file> [model] [max-seconds]}"
PROMPT="${2:?missing prompt file}"
MODEL="${3:-google-antigravity/gemini-3.7-flash:high}"
MAXTIME="${4:-900}"

[ -f "$PROMPT" ] || { echo "prompt file not found: $PROMPT" >&2; exit 2; }
# The run below cd's into WORKDIR, so a relative prompt path would not resolve.
PROMPT="$(cd "$(dirname "$PROMPT")" && pwd)/$(basename "$PROMPT")"

WORKDIR="$REPO/research/_work/$TOPIC"
mkdir -p "$WORKDIR"

# Quota gate. Which pool to check depends on the provider in the model string.
case "$MODEL" in
  google-antigravity/*) LABEL="Usage (Google)" ;;
  synthetic/*)          LABEL="Synthetic Requests" ;;
  *)                    LABEL="" ;;
esac

if [ -n "$LABEL" ]; then
  PCT="$(quota_pct "$LABEL")"
  if [ -n "$PCT" ]; then
    echo "quota for '$LABEL': ${PCT}% used" >&2
    if [ "${PCT%%.*}" -ge "$QUOTA_CEILING" ]; then
      echo "REFUSING: pool is at ${PCT}%, ceiling is ${QUOTA_CEILING}%." >&2
      echo "Run 'tools/omp-run.sh status' for the reset time." >&2
      exit 3
    fi
  else
    echo "WARNING: could not read quota for '$LABEL'; continuing" >&2
  fi
fi

BEFORE="$(agent_pids)"
trap 'reap "$BEFORE"' EXIT INT TERM

echo "topic=$TOPIC model=$MODEL max=${MAXTIME}s tools=$TOOLS" >&2

set +e
(
  cd "$WORKDIR"
  NO_COLOR=1 timeout --kill-after=30 "$((MAXTIME + 60))" \
    omp -p \
      --model "$MODEL" \
      --config "$CONFIG" \
      --no-session --auto-approve --no-skills \
      --tools "$TOOLS" \
      --max-time "$MAXTIME" \
      < "$PROMPT"
) > "$WORKDIR/run.log" 2>&1
RC=$?
set -e

echo "exit=$RC log=$WORKDIR/run.log" >&2
# Name every file the run left behind, so a session never has to guess
# where a delegate wrote its report (models have mis-nested relative
# paths; foreground shell views can lag the real filesystem).
echo "workdir files: $(cd "$WORKDIR" && ls -m 2>/dev/null)" >&2
grep -qiE '429|RESOURCE_EXHAUSTED|quota' "$WORKDIR/run.log" 2>/dev/null \
  && echo "QUOTA ERROR in run.log - check before retrying" >&2

exit "$RC"
