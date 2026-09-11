#!/usr/bin/env bash
# Liveness and health probe for the agy fleet.
#
# There is no `agy usage` and no quota subcommand (v1.2.1, 2026-09-11), so a
# real probe request is the only way to learn whether the pool answers. This
# runs the cheapest one available.
#
# Usage: agy-check.sh
# Exit 0 if the probe came back with OK, 1 otherwise.

set -euo pipefail

PROBE_MODEL="${AGY_PROBE_MODEL:-gemini-3.8-flash-low}"

# Capture first, then print. A `cmd | head -1` closes the pipe on the writer
# and the resulting SIGPIPE would fire a bogus "failed" branch.
VERSION="$(agy --version 2>&1 || true)"
RC_STATUS="$(timeout 30 agy remote-control status 2>&1 || true)"
MODELS="$(timeout 60 agy models 2>&1 || true)"

echo "--- agy version ---"
echo "${VERSION%%$'\n'*}"

echo "--- remote-control ---"
echo "${RC_STATUS%%$'\n'*}"

echo "--- gemini-3.8 models ---"
grep -E '^gemini-3\.8-' <<<"$MODELS" || echo "no gemini-3.8-* models listed"

echo "--- probe ($PROBE_MODEL) ---"
START="$(date +%s)"
# stderr is kept apart from the answer: a warning or a banner on stderr that
# happens to contain "OK" must not pass the probe.
ERRFILE="$(mktemp)"
set +e
OUT="$(timeout 60 agy --model "$PROBE_MODEL" \
  --print="Reply with exactly the word OK and nothing else." 2>"$ERRFILE")"
RC=$?
set -e
ERR="$(cat "$ERRFILE")"
rm -f "$ERRFILE"
WALL=$(( $(date +%s) - START ))

echo "exit_code=$RC wall_seconds=$WALL"
echo "reply: ${OUT:0:200}"

# Trim each line, drop the empty ones, and demand a line that is exactly OK;
# a plain `grep -q OK` also passes on "I cannot say OK".
ANSWER="$(awk '{gsub(/^[ \t\r]+|[ \t\r]+$/, ""); if ($0 != "") print}' <<<"$OUT")"

if [ "$RC" -eq 0 ] && grep -qx 'OK' <<<"$ANSWER"; then
  echo "RESULT: agy fleet is answering"
  exit 0
fi

echo "stderr: ${ERR:0:200}"
if grep -qiE '429|RESOURCE_EXHAUSTED|quota|rate limit' <<<"$OUT$ERR"; then
  echo "RESULT: quota or rate limit - use omp-fleet as fallback"
else
  echo "RESULT: agy fleet did NOT answer"
fi
exit 1
