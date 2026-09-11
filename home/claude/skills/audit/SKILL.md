---
name: audit
description: Pre-commit audit of a change - an internal read-only auditor subagent plus one external model on the agy fleet (omp fleet as fallback) (one external model for all code, risky code included). Use before any commit the operator asked for, when the operator says "audit", "denetle", "review before commit", or when a delegate reports a change as done. Do NOT use for style review, for work still in progress, or for doc-only edits under ten lines (the internal auditor alone is enough there).
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
   ignores `research/_work/`, otherwise under the session scratchpad with
   `AGY_PROJECT_ROOT` (or `OMP_PROJECT_ROOT` for a fallback run) pointing
   there. Never leave audit files in a tracked
   tree. Save the diff as `diff.patch` and the spec as `spec.md`.
2. Internal: `Agent(auditor)` with the spec, the absolute path of the diff,
   the repo path, and - on a re-audit - exactly what the previous round
   found, so it attacks the fix instead of re-reporting the bug. An
   internal pass is a claim too; it has returned zero findings on code an
   external audit then found major defects in.
3. External: invoke the `agy-fleet` skill, then one launch per auditor,
   as ONE Bash call with `run_in_background: true` that launches and
   waits; the harness notifies when it ends and the session keeps
   working (the internal auditor runs in parallel) instead of blocking:

   ```
   Bash(run_in_background: true,
        command: "$AGY_RUN audit-<topic>-gemini38 <workdir>/prompt.txt gemini-3.8-flash-high 900 && $AGY_WAIT audit-<topic>-gemini38 900")
   ```

   Do not call `$AGY_WAIT` in the foreground: it blocks the session for
   the whole run (380 s measured 2026-09-11) and a long audit hits the
   Bash tool's 10-minute cap.

   The run writes its own directory, `research/_work/audit-<topic>-gemini38/`
   - not the scope directory `audit-<topic>/` from step 1 - so `report.md`,
   `meta` and `run.log` are there. (The prompt template's "Report ... to
   <path>/report.md" points at the scope directory on purpose.)

   One external auditor per round. Read `report.md`, not the reply, and
   confirm `model_answered` in `meta` before crediting the model.

   FALLBACK, only when the agy run reports `status` `quota` or `error`:
   invoke `omp-fleet` and run one background Bash call, no `&`:

   ```
   exec $OMP_RUN audit-<topic>-<model-short> <workdir>/prompt.txt <model> 900
   ```

   Confirm the answering model in the omp log before crediting it (omp has
   walked a fallback chain onto another pool without saying so).
4. Arbitrate. For each finding, open the code and confirm the failure
   scenario. Verified findings are fixed (by `executor` or by you); the rest
   are recorded as rejected with one line why. Do not fix what you have not
   confirmed, and do not drop a finding because two auditors disagree.
5. Re-audit only the fix, with the previous findings in the prompt. Two
   rounds is the norm; a third means the spec was wrong, so stop and say so.
6. The commit body gets one line: `Audit: internal <verdict>, agy
   gemini-3.8-flash-high <verdict>; <n> findings fixed, <m> rejected.`
   If the fallback was used, the line names the omp model that actually
   answered instead: `Audit: internal <verdict>, omp <answering-model>
   <verdict>; <n> findings fixed, <m> rejected.`

## Models

Pinned by direct name; aliases are remapped by the provider without notice.

| Role | Model |
|---|---|
| external, always (risky code included) | agy fleet, `gemini-3.8-flash-high` |
| external fallback, only on agy status quota or error | omp fleet, `google-antigravity/gemini-3.8-flash:high` |
| second external | SUSPENDED by owner decision 2026-09-04 until re-enabled - was `synthetic/hf:zai-org/GLM-5.2:high`; do not run it |
| never | `synthetic/syn:small:text:high` (fabricates findings; arbitrating a fabricated finding costs more than the audit saves) |

Never use a `syn:*` alias for an audit. Before a fallback run, check
`$OMP_RUN status` if a project of the operator's is running a live model on
the same pool. agy has no quota subcommand; `agy-check.sh` is the probe.

## External prompt template

```
You are an adversarial code auditor. Assume the change is broken and try to
prove it. Read-only: never edit files.

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
spawn anything. Reply in at most five lines; the report file is the
deliverable.
```
