#!/usr/bin/env bash
# Block until an agy-run.sh run finishes, then print its status line.
#
# Usage: agy-wait.sh <topic> [max-seconds=900] [poll-seconds=10]
#
# The waiter's own deadline is max-seconds plus a 90 s grace, because the run
# keeps its pid alive while it parses the stream and writes meta - with the
# same number on both sides the waiter would give up on a run that is only
# finishing its post-processing.
#
# Liveness is `kill -0` on the pid agy-run.sh wrote. Never pgrep: this
# script's own command line contains both "agy" and the topic name, so any
# pattern match would find itself.
#
# Exit codes mirror the run: 0 status=ok, 1 status=error, 3 status=quota,
# 5 status=timeout (the run's own timeout), 6 this waiter gave up first.

set -euo pipefail

REPO="${AGY_PROJECT_ROOT:-${OMP_PROJECT_ROOT:-$PWD}}"
TOPIC="${1:?usage: agy-wait.sh <topic> [max-seconds] [poll-seconds]}"
MAXWAIT="${2:-900}"
POLL="${3:-10}"

WORKDIR="$REPO/research/_work/$TOPIC"
[ -d "$WORKDIR" ] || { echo "no work dir: $WORKDIR" >&2; exit 1; }

GRACE=90
DEADLINE=$((MAXWAIT + GRACE))

WAITED=0
while [ -f "$WORKDIR/pid" ]; do
  PID="$(cat "$WORKDIR/pid" 2>/dev/null || true)"
  [ -n "$PID" ] || break
  kill -0 "$PID" 2>/dev/null || break
  if [ "$WAITED" -ge "$DEADLINE" ]; then
    echo "topic=$TOPIC still running after ${WAITED}s (pid $PID); not killed" >&2
    exit 6
  fi
  sleep "$POLL"
  WAITED=$((WAITED + POLL))
done

# The run writes status and only then removes pid, so re-read once after the
# pid is gone rather than reporting a status that was read a moment too early.
STATUS="$(cat "$WORKDIR/status" 2>/dev/null || echo unknown)"
if [ "$STATUS" = "running" ]; then
  sleep 2
  STATUS="$(cat "$WORKDIR/status" 2>/dev/null || echo unknown)"
fi
echo "topic=$TOPIC status=$STATUS waited=${WAITED}s"
sed -n 's/^/  /p' "$WORKDIR/meta" 2>/dev/null || true

case "$STATUS" in
  ok)      exit 0 ;;
  quota)   exit 3 ;;
  timeout) exit 5 ;;
  *)       exit 1 ;;
esac
