#!/usr/bin/env bash
# Safe launcher for delegated agy (Google Antigravity CLI) runs.
#
# Shape is copied from omp-fleet/omp-run.sh: one topic directory under
# research/_work/, a prompt file on disk, a single process, a run.log, and a
# report the caller reads afterwards. The differences are forced by agy:
#
#   1. agy has NO quota/usage subcommand (checked against `agy --help` and
#      `agy help`, v1.2.1, 2026-09-11). There is nothing to gate on before the
#      run, so quota is detected after the fact from the output (429 /
#      RESOURCE_EXHAUSTED / rate limit) and reported as status=quota.
#   2. agy takes its prompt on the command line (`--print=...`). Linux caps a
#      single argv entry at 128 KiB (MAX_ARG_STRLEN), and an audit prompt with
#      a whole diff in it is bigger than that - a 213 KB prompt died with
#      "Argument list too long" before agy was even exec'd. So this script
#      feeds the prompt over stdin as one NDJSON message
#      (--input-format stream-json), which was measured good to 190 KB.
#      Above ~192 KiB agy silently truncates the tail of a stdin message, so
#      larger prompts are handed over as a FILE the model is told to read.
#   3. agy backgrounds itself here (setsid + a pid file), instead of relying on
#      the caller's Bash(run_in_background). Liveness is then `kill -0 <pid>`
#      on a pid this script wrote, never pgrep on a pattern.
#
# agy is NOT sandboxed by this wrapper. In print mode its permission_mode is
# "always-proceed" and its tool list includes run_command, write_to_file,
# invoke_subagent and a browser. `--sandbox` was measured NOT to be a
# boundary: the model was still able to run a shell command by asking for
# "bypass sandbox mode". Read-only behaviour must be demanded in the prompt.
# What this wrapper does contain is the blast radius: cwd and --add-dir are
# the topic directory, so files the model writes land there.
#
# Usage:
#   agy-run.sh <topic> <prompt-file> [model] [max-seconds]
#   agy-run.sh status <topic>          # one status line for a topic
#
# Exit codes: 0 launched, 2 bad arguments or prompt file missing, 4 a run is
# already alive (or a launch is in progress).

set -euo pipefail

# Work root. AGY_PROJECT_ROOT is the name of this fleet; OMP_PROJECT_ROOT is
# accepted too so a caller that already exported it for the omp fallback does
# not have to export a second variable.
REPO="${AGY_PROJECT_ROOT:-${OMP_PROJECT_ROOT:-$PWD}}"

# Largest stdin message that is safe to inline. agy truncates a stdin message
# at roughly 192 KiB (measured 2026-09-11: a 213 KB prompt came back with
# "the last ~21 KB was cut off"); 190 KB round-trips intact. The limit is
# measured on the ENCODED NDJSON line, not on the prompt file: JSON escaping
# of newlines, quotes and backslashes makes the line bigger than its source.
INLINE_MAX=180000

SELF="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

status_line() {
  local wd="$1"
  local st="unknown"
  [ -f "$wd/status" ] && st="$(cat "$wd/status")"
  echo "topic=$(basename "$wd") status=$st $(tr '\n' ' ' <"$wd/meta" 2>/dev/null || true)"
}

if [ "${1:-}" = "status" ]; then
  TOPIC="${2:?usage: agy-run.sh status <topic>}"
  WD="$REPO/research/_work/$TOPIC"
  [ -d "$WD" ] || { echo "no work dir: $WD" >&2; exit 1; }
  status_line "$WD"
  exit 0
fi

USAGE="usage: agy-run.sh <topic> <prompt-file> [model] [max-seconds]"
# A missing argument is the same class of caller error as a missing prompt
# file, so it exits 2 as well; ${2:?} would exit 1 and read as a real failure.
if [ $# -lt 2 ] || [ -z "${1:-}" ] || [ -z "${2:-}" ]; then
  echo "$USAGE" >&2
  exit 2
fi
TOPIC="$1"
PROMPT="$2"
MODEL="${3:-gemini-3.8-flash-high}"
MAXTIME="${4:-900}"

[ -f "$PROMPT" ] || { echo "prompt file not found: $PROMPT" >&2; exit 2; }
PROMPT="$(cd "$(dirname "$PROMPT")" && pwd)/$(basename "$PROMPT")"

WORKDIR="$REPO/research/_work/$TOPIC"
mkdir -p "$WORKDIR"

# Refuse to race an existing run. Two launches that read the pid file at the
# same time would both find it dead and both write, so the lock is an atomic
# mkdir taken BEFORE any file is written and released as soon as the pid file
# exists. A lock older than 60 s with no live pid behind it is a crashed
# launch and is cleared once.
LOCK="$WORKDIR/.launch.lock"
if ! mkdir "$LOCK" 2>/dev/null; then
  LOCK_AGE=$(( $(date +%s) - $(stat -c %Y "$LOCK" 2>/dev/null || echo 0) ))
  HELD="$(cat "$WORKDIR/pid" 2>/dev/null || true)"
  if { [ -n "$HELD" ] && kill -0 "$HELD" 2>/dev/null; } || [ "$LOCK_AGE" -lt 60 ]; then
    echo "REFUSING: a launch is in progress or a run is alive for topic '$TOPIC'" >&2
    echo "Wait for it (agy-wait.sh $TOPIC) or kill the pid in $WORKDIR/pid first." >&2
    exit 4
  fi
  rmdir "$LOCK" 2>/dev/null || true
  mkdir "$LOCK" 2>/dev/null || { echo "REFUSING: cannot take launch lock $LOCK" >&2; exit 4; }
fi
trap 'rmdir "$LOCK" 2>/dev/null || true' EXIT

# Liveness is kill -0 on OUR pid file; never pgrep for "agy", because this
# script's own command line contains that word.
if [ -f "$WORKDIR/pid" ]; then
  OLD="$(cat "$WORKDIR/pid" 2>/dev/null || true)"
  if [ -n "$OLD" ] && kill -0 "$OLD" 2>/dev/null; then
    echo "REFUSING: run already alive for topic '$TOPIC' (pid $OLD)" >&2
    echo "Wait for it (agy-wait.sh $TOPIC) or kill $OLD first." >&2
    exit 4
  fi
  rm -f "$WORKDIR/pid"
fi

# The documented workflow writes the prompt straight to <workdir>/prompt.txt,
# so the copy is often a no-op on itself; cp would fail on that.
if [ "$PROMPT" != "$WORKDIR/prompt.txt" ]; then
  cp -f "$PROMPT" "$WORKDIR/prompt.txt"
fi
PROMPT_BYTES="$(wc -c <"$WORKDIR/prompt.txt" | tr -d ' ')"

# Build the single stdin NDJSON message and decide the transport from the
# ENCODED line, which is what agy truncates - not from the prompt file. Small
# prompts go inline; large ones become a pointer at prompt.txt, which the
# model reads with its file tools (measured: a 213 KB prompt answered
# correctly this way in 57 s).
DECISION="$(python3 - "$WORKDIR/prompt.txt" "$WORKDIR/input.ndjson" "$INLINE_MAX" <<'PY'
import json
import sys

src, dst, limit = sys.argv[1], sys.argv[2], int(sys.argv[3])

# The pointer carries the same hard rules the inline prompts carry, because
# the model acts on this text before it has read prompt.txt.
POINTER = (
    "Your task is written in the file prompt.txt in the directory that is "
    "in your workspace. Read ALL of it - it is large, so keep reading "
    "until you reach the end of the file - and then do exactly what it "
    "says. Do NOT spawn subagents and do not use invoke_subagent. Do not "
    "edit or create any file outside that directory. Answer in this "
    "conversation in at most five lines; do not create any new files.\n"
)


def encode(text):
    msg = {"event": "user", "message": {"role": "user", "content": text}}
    # ensure_ascii=False: \uXXXX escaping would inflate the line agy measures
    # for no gain, since the stream is UTF-8 either way.
    line = json.dumps(msg, ensure_ascii=False) + "\n"
    return line, len(line.encode("utf-8"))


with open(src, encoding="utf-8", errors="replace") as fh:
    line, nbytes = encode(fh.read())
transport = "inline"
if nbytes > limit:
    transport = "file"
    line, nbytes = encode(POINTER)
with open(dst, "w", encoding="utf-8") as fh:
    fh.write(line)
print(transport)
print(nbytes)
PY
)"
TRANSPORT="$(sed -n 1p <<<"$DECISION")"
NDJSON_BYTES="$(sed -n 2p <<<"$DECISION")"
[ -n "$TRANSPORT" ] || { echo "failed to build $WORKDIR/input.ndjson" >&2; exit 2; }

STARTED="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
START_EPOCH="$(date +%s)"

{
  echo "topic=$TOPIC"
  echo "model_requested=$MODEL"
  echo "model_answered=unknown"
  echo "effort=model-suffix"
  echo "transport=$TRANSPORT"
  echo "started_utc=$STARTED"
  echo "finished_utc="
  echo "exit_code="
  echo "wall_seconds="
  echo "prompt_bytes=$PROMPT_BYTES"
  echo "ndjson_bytes=$NDJSON_BYTES"
} >"$WORKDIR/meta"
echo running >"$WORKDIR/status"
: >"$WORKDIR/run.log"
: >"$WORKDIR/raw.json"
: >"$WORKDIR/report.md"

# The whole run, including the post-processing, happens in the background so
# the caller gets its shell back immediately and polls the pid file.
# shellcheck disable=SC2329  # invoked indirectly via `declare -f` in bash -c
run_body() {
  cd "$WORKDIR"

  # A killed worker must not leave status=running forever. The handler only
  # fires while status is still "running", so the normal path's own
  # ok/timeout/quota/error always wins.
  # shellcheck disable=SC2329  # called from the traps below
  worker_trap() {
    local sig="${1:-EXIT}"
    if [ "$(cat "$WORKDIR/status" 2>/dev/null || true)" = "running" ]; then
      [ -n "${AGY_CHILD:-}" ] && kill -TERM "$AGY_CHILD" 2>/dev/null
      echo "worker terminated before the run finished (signal $sig)" \
        >>"$WORKDIR/run.log"
      echo error >"$WORKDIR/status"
      rm -f "$WORKDIR/pid"
    fi
    return 0
  }
  trap 'worker_trap TERM; exit 143' TERM
  trap 'worker_trap INT; exit 130' INT
  trap 'worker_trap EXIT' EXIT

  set +e
  # No --foreground: detached already, and the default form puts agy in its
  # own process group and kills the GROUP on timeout, which takes agy's own
  # children with it. (Children spawned by the machine-wide
  # antigravity-cli-daemon are outside any group this script controls.)
  timeout --kill-after=30 "$MAXTIME" \
    agy --model "$MODEL" \
        --print-timeout "${MAXTIME}s" \
        --add-dir "$WORKDIR" \
        --disable-slash-commands \
        --input-format stream-json \
        --output-format stream-json \
        <"$WORKDIR/input.ndjson" \
        >"$WORKDIR/raw.json" 2>>"$WORKDIR/run.log" &
  # Backgrounded and waited on, not run in the foreground: bash defers a trap
  # until a foreground command returns, which would make the TERM handler
  # above useless for the whole length of a run.
  AGY_CHILD=$!
  wait "$AGY_CHILD"
  local rc=$?
  AGY_CHILD=""
  set -e

  local finished wall
  finished="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  wall="$(( $(date +%s) - START_EPOCH ))"

  # Extract the answer text, the model agy says it started with, and the
  # result event's own status/error. Parsing the error out of the JSON keeps
  # the quota check off the model's prose: an audit that merely discusses the
  # word "quota" must not be reported as a quota failure.
  local parsed answered result_status result_error
  parsed="$(python3 - "$WORKDIR/raw.json" "$WORKDIR/report.md" <<'PY'
import json
import sys

raw, out = sys.argv[1], sys.argv[2]
answered = "unknown"
status = "none"
error = ""
response = ""
results = 0
# Any surprise in the third-party stream must end in a written status, never
# in an unhandled exception: the caller classifies on these four lines.
try:
    with open(raw, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                ev = json.loads(line)
            except ValueError:
                continue
            if not isinstance(ev, dict):
                continue
            if ev.get("event") == "init":
                init = ev.get("init")
                if isinstance(init, dict):
                    answered = init.get("model") or answered
            elif ev.get("event") == "result":
                results += 1
                res = ev.get("result")
                if not isinstance(res, dict):
                    status = "MALFORMED_RESULT"
                    continue
                response = res.get("response") or ""
                status = res.get("status") or status
                error = str(res.get("error") or "").replace("\n", " ")
except Exception as exc:  # noqa: BLE001 - classified by the caller
    status = "PARSE_ERROR"
    error = f"parser: {exc!r}"
try:
    with open(out, "w", encoding="utf-8") as fh:
        fh.write(response)
except OSError as exc:
    status = "PARSE_ERROR"
    error = f"report write: {exc!r}"
# One value per line for the bash readback: nothing from the stream may
# carry a newline into it, or every later field shifts by one.
one_line = lambda v: str(v).replace("\r", " ").replace("\n", " ")  # noqa: E731
print(one_line(answered))
print(one_line(status))
print(one_line(error))
print(results)
PY
)" || parsed=$'unknown\nPARSE_ERROR\nparser process failed\n0'
  answered="$(sed -n 1p <<<"$parsed")"
  result_status="$(sed -n 2p <<<"$parsed")"
  result_error="$(sed -n 3p <<<"$parsed")"
  local result_events
  result_events="$(sed -n 4p <<<"$parsed")"
  result_events="${result_events:-0}"

  local report_bytes
  report_bytes="$(wc -c <"$WORKDIR/report.md" | tr -d ' ')"

  local status
  if grep -qiE '429|RESOURCE_EXHAUSTED|quota|rate limit' "$WORKDIR/run.log" \
      2>/dev/null || grep -qiE '429|RESOURCE_EXHAUSTED|quota|rate limit' \
      <<<"$result_error"; then
    status=quota
    rc=3
  elif [ "$rc" -eq 124 ] || [ "$rc" -eq 137 ]; then
    status=timeout
  elif grep -q 'print timeout after' "$WORKDIR/run.log" 2>/dev/null; then
    # agy's own --print-timeout fired: it returns rc 0, one SUCCESS result
    # and whatever partial text it had. A cut answer is not a report.
    status=timeout
    result_error="agy print timeout with turn in progress (partial output discarded from status); $result_error"
  elif [ "$rc" -ne 0 ] || [ "$result_status" = "ERROR" ]; then
    status=error
  elif [ "$result_status" = "PARSE_ERROR" ] || [ "$result_status" = "MALFORMED_RESULT" ]; then
    status=error
  elif [ "$result_events" -ne 1 ]; then
    # Zero result events is a cut stream; more than one means something
    # (a subagent, a retry) answered twice and the last one won silently.
    # Neither is a report anyone should credit.
    status=error
    result_error="expected exactly one result event, saw $result_events; $result_error"
  elif [ "$report_bytes" -eq 0 ]; then
    status=error
  else
    status=ok
  fi

  {
    echo "topic=$TOPIC"
    echo "model_requested=$MODEL"
    echo "model_answered=$answered"
    echo "effort=model-suffix"
    echo "transport=$TRANSPORT"
    echo "started_utc=$STARTED"
    echo "finished_utc=$finished"
    echo "exit_code=$rc"
    echo "wall_seconds=$wall"
    echo "prompt_bytes=$PROMPT_BYTES"
    echo "ndjson_bytes=$NDJSON_BYTES"
    echo "report_bytes=$report_bytes"
    echo "result_status=$result_status"
    echo "result_events=$result_events"
    echo "result_error=$result_error"
  } >"$WORKDIR/meta"
  echo "$status" >"$WORKDIR/status"
  rm -f "$WORKDIR/pid"
}

# run_body executes in a fresh `bash -c`, which inherits only exported vars.
export WORKDIR MODEL MAXTIME TOPIC STARTED START_EPOCH PROMPT_BYTES TRANSPORT NDJSON_BYTES

if command -v setsid >/dev/null 2>&1; then
  setsid nohup bash -c "$(declare -f run_body); run_body" \
    >>"$WORKDIR/run.log" 2>&1 &
else
  nohup bash -c "$(declare -f run_body); run_body" \
    >>"$WORKDIR/run.log" 2>&1 &
fi
BGPID=$!
echo "$BGPID" >"$WORKDIR/pid"
rmdir "$LOCK" 2>/dev/null || true
trap - EXIT

echo "launched topic=$TOPIC model=$MODEL max=${MAXTIME}s transport=$TRANSPORT prompt_bytes=$PROMPT_BYTES pid=$BGPID"
echo "workdir=$WORKDIR"
echo "poll: $SELF/agy-wait.sh $TOPIC"
exit 0
