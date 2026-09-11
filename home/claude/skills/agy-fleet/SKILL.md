---
name: agy-fleet
description: Delegate external audits and large-output work (bulk extraction, document summarization, long drafts, second-opinion reviews) to the local `agy` Antigravity CLI on a separate Google subscription, so the work does not consume Claude Code session limits. Use whenever a task would pull more than ~2k tokens of material into context, and for every external audit since 2026-09-11 - omp-fleet is the fallback only when an agy run reports status quota or error.
---

# agy-fleet - delegating work off the Claude quota

A Claude subagent bills its whole token usage to the operator's Claude limit.
The same machine has `agy` (Google Antigravity CLI, v1.2.1) authenticated
against a separate Google subscription. Work routed through `agy` costs this
session only the short report that comes back. This is quota arbitrage, not a
quality upgrade: the delegated models are weaker than the one running this
session. Route retrieval, bulk work and second opinions to them; keep judgment
here.

**Since 2026-09-11 this is the path for perp-lab's external audits.**
The `audit` skill invokes `agy-run.sh` with `gemini-3.8-flash-high`.
`omp-fleet` stays installed as the FALLBACK, used only when an agy run
reports `status` `quota` or `error`.

## What to delegate, what to keep

| Delegate | Keep in this session |
|---|---|
| External audits of a finished diff, bulk extraction, reformatting, summarization of long documents, first drafts of reference material | Strategy, decisions, ADRs, roadmap, handoff files - anything that says what the findings mean, and the decision to accept or reject each audit finding |

## Model policy

Pin by FULL model name from `agy models`. Do not use a display name
("Gemini 3.8 Flash (High)"); the CLI accepts it but rewrites it.

| Task | Model |
|---|---|
| External audits, any review that must catch a real bug | `gemini-3.8-flash-high` |
| Cheap extraction, reformatting, health probes | `gemini-3.8-flash-low` |
| Overflow if 3.8 is unavailable | `gemini-3.7-flash-high` |
| Never | `claude-sonnet-4-6`, `claude-opus-4-6-thinking` - the operator reserves that allowance, and an Anthropic model is not an independent second opinion of a Claude session |

Effort is part of the model name (`-high` / `-medium` / `-low`); the separate
`--effort` flag is not used by the wrapper.

## How the prompt reaches agy, and why

`agy --print="<prompt>"` works but is unusable for audits: Linux caps one argv
entry at 128 KiB, and a 213 KB prompt died with `Argument list too long`
before agy was even exec'd (measured 2026-09-11). So `agy-run.sh` feeds the
prompt over **stdin as one NDJSON message**:

    agy --model <model> --add-dir <workdir> --disable-slash-commands \
        --input-format stream-json --output-format stream-json \
        < input.ndjson

where `input.ndjson` is one line:
`{"event":"user","message":{"role":"user","content":"<prompt>"}}`.

Measured limits, same day: 190 KB inline round-trips with the tail intact;
213 KB comes back with the last ~21 KB silently cut off (agy truncates a
stdin message at roughly 192 KiB). So the wrapper inlines up to 180,000
bytes - measured on the ENCODED NDJSON line, not on the prompt file, because
JSON escaping makes the line bigger than its source - and above that copies
the prompt to `prompt.txt` in the work dir and sends a short pointer telling
the model to read the whole file (carrying the same hard rules as an inline
prompt: read it all, no subagents, no edits outside the work dir, at most
five lines) - a 213 KB audit
prompt answered correctly that way in 57 s. `meta` records which transport
was used (`transport=inline` or `transport=file`) and the measured
`ndjson_bytes`.

## What agy can still do

There is no tool allowlist. In print mode agy reports
`permission_mode: always-proceed` and a tool list that includes
`run_command`, `write_to_file`, `invoke_subagent`, `search_web` and a
browser. `--sandbox` is **not** a boundary: in a test the model was blocked
by the sandbox on a shell command and then re-ran it in "bypass sandbox
mode" and succeeded. `--mode plan` is also not usable here - it warns it has
no effect while `--disable-slash-commands` is set.

What the wrapper does instead is bound the blast radius: cwd and `--add-dir`
are the topic work dir, so files the model writes land there. (With no
`--add-dir`, agy writes into `~/.gemini/antigravity-cli/scratch/` instead,
ignoring the shell's cwd.) Everything else must be demanded in the prompt -
see the template.

## Hard rules

1. **One delegate is one process.** The prompt must forbid subagents and the
   `invoke_subagent` tool. agy's machine-wide `antigravity-cli-daemon` can
   outlive the run's process group, and the equivalent incident on the omp
   fleet drained a full day of quota on two pools.
2. **The runner backgrounds itself; do not background it again.** Call
   `agy-run.sh` in the foreground - it returns in under a second after
   writing `pid`. An extra `&` or `run_in_background` is harmless but adds a
   second process to reason about.
3. **Liveness is `kill -0 $(cat <workdir>/pid)`, never `pgrep`.** Your own
   command line contains both `agy` and the topic name; a pattern match finds
   itself. `agy-wait.sh <topic> [max-seconds]` does the polling (every 10 s); its own
   deadline is max-seconds plus a 90 s grace, so a run that is still writing
   its meta is not reported as abandoned.
4. **Always set a timeout.** Default 900 s. A run that has to be killed by
   hand has already cost more than it saved. The runner passes the same
   value as agy's `--print-timeout`; agy's own default is 5 minutes, and
   an audit that reads a diff with tools needs more than that (observed
   2026-09-11: cut at 5m0s with `report_bytes=0`, `status=error`).
5. **Confirm the answering model before crediting it.** Read
   `model_answered` in `<workdir>/meta`; it comes from agy's own `init`
   event. If it is `unknown` or differs from `model_requested`, say so and do
   not name the model in a commit line.
6. **Never put a secret in the prompt file.** It is copied into the work dir
   and sent to a third-party API. Exchange keys, API passwords and `op://`
   resolved values never appear in a prompt.
7. **Work in an isolated directory.** `research/_work/<topic>/` under the
   work root, which is already gitignored in perp-lab (`.gitignore:19`).
   Confirm the same line exists before using this skill in another repo. The
   work root is `AGY_PROJECT_ROOT`, or `OMP_PROJECT_ROOT` if that is unset
   (so one export serves both fleets), or `$PWD`.
8. **Verify before promoting.** Delegate output is a claim, not a finding.
   Recompute derived numbers; open the file at the path:line an audit
   finding names before accepting it. A finding you cannot reproduce in the
   source is rejected, not fixed.
9. **Delete the work dir when the run's output has been merged**, or leave it
   as provenance - but never leave a half-read run behind with no note.

## Invocation

```bash
AGY_RUN=~/.claude/skills/agy-fleet/scripts/agy-run.sh
AGY_WAIT=~/.claude/skills/agy-fleet/scripts/agy-wait.sh
```

Write the prompt file with the harness **Write** tool, not a shell heredoc: a
sandboxed foreground shell has held a heredoc write in an overlay the
detached run could not see (measured on omp-fleet, 2026-08-28), and the two
wrappers share that failure mode.

```
Write(file_path: <abs-repo>/research/_work/<topic>/prompt.txt, content: ...)
Bash("$AGY_RUN <topic> <abs-repo>/research/_work/<topic>/prompt.txt gemini-3.8-flash-high 900")
Bash("$AGY_WAIT <topic> 900")          # blocks, prints the status line
Read(<abs-repo>/research/_work/<topic>/report.md)
Read(<abs-repo>/research/_work/<topic>/meta)   # confirm model_answered
```

The prompt path is absolute. `agy-run.sh status <topic>` prints the current
status line without waiting. `agy-check.sh` probes the fleet (version,
daemon, gemini-3.8 models, and a real one-word request) and exits 0 only if
the probe answered.

### Input -> Output example

Input, `research/_work/audit-risk-shell-gemini38/prompt.txt`:

```
You are an external code auditor. Review the diff below for correctness bugs,
lookahead, and unsafe order handling. Reply with a numbered list of findings,
each as: SEVERITY | file:line | what is wrong | why it matters. If you find
nothing, say NO FINDINGS. Do not use subagents or the invoke_subagent tool.
Do not run shell commands. Do not write files. Answer in this conversation.

--- diff ---
<git diff>
```

Command and output:

```
$ $AGY_RUN audit-risk-shell-gemini38 .../prompt.txt gemini-3.8-flash-high 900
launched topic=audit-risk-shell-gemini38 model=gemini-3.8-flash-high max=900s
transport=inline prompt_bytes=41233 pid=31872
workdir=/home/agent/work/perp-lab/research/_work/audit-risk-shell-gemini38

$ $AGY_WAIT audit-risk-shell-gemini38 900
topic=audit-risk-shell-gemini38 status=ok waited=40s
  model_requested=gemini-3.8-flash-high
  model_answered=gemini-3.8-flash-high
  exit_code=0
  wall_seconds=38
```

`report.md` then holds the findings text; `raw.json` holds every agy event.

## Files the run leaves behind

`research/_work/<topic>/`: `prompt.txt` (copy of the prompt),
`input.ndjson` (what was sent), `raw.json` (the full stream-json event log),
`report.md` (the answer text only), `run.log` (agy's stderr), `pid` (removed
when the run ends), `meta`, `status`.

`meta` keys: `topic`, `model_requested`, `model_answered`, `effort`,
`transport`, `started_utc`, `finished_utc`, `exit_code`, `wall_seconds`,
`prompt_bytes`, `ndjson_bytes` (the encoded stdin line, what the inline
limit is measured on), `report_bytes`, `result_status`, `result_events`,
`result_error`.

## How to read failures

`agy-run.sh` exits 0 as soon as the run is launched; the run's own outcome is
in `status` and `meta`.

| Signal | Meaning | Do |
|---|---|---|
| `agy-run.sh` exit 2 | prompt file not found | check the path is absolute |
| `agy-run.sh` exit 4 | a run is already alive for this topic | `agy-wait.sh <topic>`, or use a new topic name |
| `agy-wait.sh` exit 6 | the waiter hit its own limit; the run is still alive and was NOT killed | wait again, or kill the pid deliberately |
| `status=ok` | report is non-empty and agy reported SUCCESS | read `report.md`, confirm `model_answered` |
| `status=timeout` (`exit_code=124` or `137`, or exit 0 with `print timeout after` in `run.log`) | the run hit `max-seconds`; in the exit-0 form agy cut its own turn and returned PARTIAL text with `status: SUCCESS`, so `report.md` is truncated and must not be credited | shorten the prompt or raise the limit; do not retry blindly |
| `status=quota` (`exit_code=3`) | 429 / RESOURCE_EXHAUSTED / rate limit in `run.log` or the result error | fall back to `omp-fleet`, and say in the commit line which model actually answered |
| `status=error` | non-zero exit, agy result `status: ERROR`, a stream the parser could not read, a `result_events` count in `meta` other than 1 (cut stream, or a second answer that would otherwise win silently), or an empty report | read `run.log` and `result_error` in `meta`. An empty report with exit 0 has been seen when the prompt was one enormous single line - reflow it and retry |
| `model_answered` is `unknown` or differs from `model_requested` | the stream gave no `init` event, or agy switched | do not credit the model; investigate before using the output |
