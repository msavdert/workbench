---
name: audit
description: Pre-commit audit of a change - an internal read-only auditor subagent plus one external model asked in one message by audit-ext.py (omp gemini-3.8-flash:high; agy and omp tool sessions as fallback), one external model for all code, risky code included. Use before any commit the operator asked for, when the operator says "audit", "denetle", "review before commit", or when a delegate reports a change as done. Do NOT use for style review, for work still in progress, or for doc-only edits under ten lines (the internal auditor alone is enough there).
---

# audit

Two independent readers, fresh context each, then the architect (you)
arbitrates. Every finding is a claim until you verify it in the code.

## Decide the variant

| Change touches | Variant |
|---|---|
| deletes data, deploys, writes to a live system, handles secrets or credentials | risky: internal + one external |
| anything else with code or config | standard: internal + one external |
| doc-only, under ten lines | internal only |

Decide from the diff, not from the task name. A "small script" that runs
`rm`, `ssh`, `curl -X POST` or reads `op://` is risky.

## Procedure

1. Scope. Write the spec (what was asked, in the operator's terms) and the
   change (`git diff`, or the commit range, or the file list) to a work
   directory: `research/_work/audit-<topic>/` under the repo if the repo
   ignores `research/_work/`, otherwise under the session scratchpad
   (`AGY_PROJECT_ROOT`, or `OMP_PROJECT_ROOT`, pointing there for a fallback
   run). Never leave audit files in a tracked tree; audit-ext refuses an
   `--out-dir` that git tracks. Save the diff as `diff.patch` and the spec
   as `spec.md`.
2. Internal: `Agent(auditor)` with the spec, the absolute path of the diff,
   the repo path, and - on a re-audit - exactly what the previous round
   found, so it attacks the fix instead of re-reporting the bug. An
   internal pass is a claim too; it has returned zero findings on code an
   external audit then found major defects in.
3. External: one message, no tools, via `audit-ext.py` next to this file
   (Python >= 3.11, standard library only, launched with `uv run`: on macOS
   `python3` is Apple's 3.9; if uv has no Python >= 3.11 yet, the first run
   downloads one, which needs the network). It inlines the spec, the
   previous findings, the diff and numbered `--file` slices, scans the prompt
   for credential shapes and secret env values, runs omp once and checks
   what came back. A round takes about 4-6 minutes (one answer of 40-50k
   thinking tokens at about 180 tokens/s) and can take up to 17 minutes
   (`--max-time` 900 plus a 120 s grace), past the Bash tool's 10-minute
   cap, so always launch it detached and watch it; the internal auditor
   runs in parallel. `<out>` is `<workdir-parent>/audit-<topic>-ext`:

   ```
   Bash(command: "rm -f <out>/launch.log <workdir>/audit-ext.out; $(command -v setsid) nohup sh -c 'uv run ~/.claude/skills/audit/audit-ext.py --topic <topic> --spec <workdir>/spec.md --diff <workdir>/diff.patch [--prev <workdir>/prev.md] [--file path:a-b ...] --out-dir <workdir-parent>; echo \"audit-ext rc=$?\"' > <workdir>/audit-ext.out 2>&1 < /dev/null & echo $! > <workdir>/audit-ext.pid")
   Monitor(command: "until grep -q '^audit-ext rc=' <workdir>/audit-ext.out 2>/dev/null || { [ -f <workdir>/audit-ext.pid ] && ! kill -0 $(cat <workdir>/audit-ext.pid) 2>/dev/null; }; do sleep 10; done; tail -3 <workdir>/audit-ext.out; tail -2 <out>/launch.log 2>/dev/null")
   ```

   The `audit-ext rc=` line in audit-ext.out is the exit code; a finished
   watch is not a passed audit. No such line means the run was killed
   (out of memory, a reboot): not credited, treat it like a killed answer
   below. rc 2 with no launch.log means a bad argument or a refused
   `--out-dir`; the reason is in audit-ext.out.
   Never wait in the foreground. `setsid` does not exist on macOS:
   `$(command -v setsid)` then expands to nothing and the same line runs
   under plain `nohup`, which is enough because the Monitor watches the
   pid file and the rc line, not the process group.

   `--file` paths are relative to `--repo-root` (default: the git top level
   of the current directory) and must stay inside it. Round 1 sends the
   whole diff plus the files the auditor needs to judge it; later rounds
   send the fix diff as `--diff` and the previous finding list as `--prev`.
   `--read-tool --max-reads N` allows a few line-ranged reads; leave it off
   unless context is missing (reads multiply the thinking time).

   The run writes `<workdir-parent>/audit-<topic>-ext/`: `prompt.txt`,
   `events.jsonl`, `report.md`, `meta.json`, and `launch.log` ending in
   `exit=<rc>`. Credit the external audit only on exit 0, read `report.md`,
   and name the model from `meta.json` `answered_by` (omp has walked a
   fallback chain onto another pool without saying so; audit-ext then
   exits 3). Exit 2 is a refusal before any request: fix the input (split
   an oversized diff, drop the secret-shaped line, move `--out-dir`); never
   route around a secret refusal through a tool session, which sends the
   same code unscanned. Exit 3 means no usable report; `meta.json`
   `problems` says why, or, when launch.log ends in `exit=3 failed:` and
   there is no meta.json, the run itself broke (omp not installed, disk
   full, an audit-ext bug): report that to the operator and use the
   FALLBACK for this round. On exit 3 for an empty answer, an answer cut at the
   token limit, or "killed after": run the same round once more unchanged;
   if it fails again, or on any other exit 3 (omp exit, error stop reason,
   another model answered), use the FALLBACK below. Any other rc (1 from a
   Python traceback) is an audit-ext bug: report it and use the FALLBACK
   for this round. One external auditor per round.

   FALLBACK, only as the exit rules above send it (an omp failure, a
   repeated empty, cut or killed answer, or an audit-ext bug): invoke the
   `agy-fleet` skill and run the tool-session template below as one
   background Bash call that launches and waits:

   ```
   Bash(run_in_background: true,
        command: "$AGY_RUN audit-<topic>-gemini38 <workdir>/prompt.txt gemini-3.8-flash-high 900 && $AGY_WAIT audit-<topic>-gemini38 900")
   ```

   It writes `research/_work/audit-<topic>-gemini38/` (`report.md`, `meta`,
   `run.log`; the template's `<path>/report.md` points at the scope
   directory on purpose); confirm `model_answered` in `meta` before
   crediting it.
   Only when that agy run reports `status` `quota` or `error`: invoke
   `omp-fleet` and run one background Bash call, no `&`:

   ```
   exec $OMP_RUN audit-<topic>-<model-short> <workdir>/prompt.txt <model> 900
   ```

   Confirm the answering model in the omp log before crediting it.
4. Arbitrate. For each finding, open the code and confirm the failure
   scenario. Verified findings are fixed (by `executor` or by you); the rest
   are recorded as rejected with one line why. Do not fix what you have not
   confirmed, and do not drop a finding because two auditors disagree.
5. Re-audit only the fix, with the previous findings in the prompt. Two
   rounds is the norm; a third means the spec was wrong, so stop and say so.
6. The commit body gets one line naming the model that answered, from
   `meta.json` `answered_by`: `Audit: internal <verdict>, omp
   <answered_by> <verdict> (audit-ext, <r> rounds); <n> findings fixed, <m>
   rejected.` If a fallback answered, name it instead: `agy
   gemini-3.8-flash-high <verdict>` or `omp <answering-model> <verdict>`.

## Models

Pinned by direct name; aliases are remapped by the provider without notice.

| Role | Model |
|---|---|
| external, always (risky code included) | omp `google-antigravity/gemini-3.8-flash:high` via `audit-ext.py` (one message, no tools) |
| external fallback, only as step 3's exit rules send it | agy fleet tool session, `gemini-3.8-flash-high` |
| second fallback, only on agy status quota or error | omp fleet tool session, `google-antigravity/gemini-3.8-flash:high` |
| second external | SUSPENDED by owner decision 2026-09-04 until re-enabled - was `synthetic/hf:zai-org/GLM-5.2:high`; do not run it |
| never | `synthetic/syn:small:text:high` (fabricates findings; arbitrating a fabricated finding costs more than the audit saves) |

Keep `:high`. Measured 2026-10-22 (perp-lab): `:medium` thinks like
`:high` (same thinking tokens and time), every lower level does not think
at all. Never use a `syn:*` alias for an audit. Before a fallback run, check
`$OMP_RUN status` if a project of the operator's is running a live model on
the same pool. agy has no quota subcommand; `agy-check.sh` is the probe.

## External prompt

audit-ext builds the message itself; do not hand-write it. Its layout,
sections joined by blank lines:

```
You are an adversarial code auditor. Assume the change is broken and try to
prove it. Never run `op`, never read ~/.config/op, ~/.ssh or any key or token
file: tool output is sent upstream.

You have no tools. Everything you need is inline below.
  (with --read-tool: the repository root, at most N line-ranged reads, no writes)

Report, in order of severity, as your reply (the reply is the deliverable):
1. Correctness bugs: file:line, the concrete input or state, the wrong outcome.
   No bug without a failure scenario.
2. Spec drift: asked vs delivered, including silently skipped items.
3. Claims in the change's own description that the code does not back up.
4. Verdict: pass | pass with findings | fail, and what you inspected to earn an
   empty list.
Style remarks only if they hide a defect. Keep the report under 80 lines.
  (80 is --report-lines)

PREVIOUS ROUND FOUND (each claimed fixed): ... CLOSED or OPEN ...   (with --prev)
=== SPEC ===
=== PREVIOUS ROUND ===                                              (with --prev)
=== DIFF ===
=== FILE <path> lines <a>-<b> (line numbers as on disk) ===         (per --file)
```

## Tool-session prompt template (fallback only)

Saved as `<workdir>/prompt.txt` for an agy or omp fleet run.

```
You are an adversarial code auditor. Assume the change is broken and try to
prove it. Read-only: never edit files other than the report below. Never
run `op`, never read
~/.config/op, ~/.ssh or any key or token file: tool output is sent upstream.

SPEC (what was asked): <path>/spec.md
CHANGE: <path>/diff.patch  (repository root: <abs repo path>)
PREVIOUS ROUND FOUND: <none | list>. Do not re-report these; audit the fix.

Report, in order of severity, to <path>/report.md:
1. Correctness bugs: file:line, the concrete input or state, the wrong
   outcome. No bug without a failure scenario.
2. Spec drift: asked vs delivered, including silently skipped items.
3. Claims in the change's own description that the code does not back up.
4. Verdict: pass | pass with findings | fail, and what you inspected to
   earn an empty list.

Style remarks only if they hide a defect. Do not use the task tool or
invoke_subagent, and do not spawn anything. Reply in at most five lines; the report file is the
deliverable.
```
