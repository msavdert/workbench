---
name: audit
description: Pre-commit audit of a change - an internal read-only auditor subagent plus one external model on the omp fleet, two external models for risky code. Use before any commit the operator asked for, when the operator says "audit", "denetle", "review before commit", or when a delegate reports a change as done. Do NOT use for style review, for work still in progress, or for doc-only edits under ten lines (the internal auditor alone is enough there).
---

# audit

Two independent readers, fresh context each, then the architect (you)
arbitrates. Every finding is a claim until you verify it in the code.

## Decide the variant

| Change touches | Variant |
|---|---|
| deletes data, deploys, writes to a live system, handles secrets or credentials | risky: internal + two external |
| anything else with code or config | standard: internal + one external |
| doc-only, under ten lines | internal only |

Decide from the diff, not from the task name. A "small script" that runs
`rm`, `ssh`, `curl -X POST` or reads `op://` is risky.

## Procedure

1. Scope. Write the spec (what was asked, in the operator's terms) and the
   change (`git diff`, or the commit range, or the file list) to a work
   directory: `research/_work/audit-<topic>/` under the repo if the repo
   ignores `research/_work/`, otherwise under the session scratchpad with
   `OMP_PROJECT_ROOT` pointing there. Never leave audit files in a tracked
   tree. Save the diff as `diff.patch` and the spec as `spec.md`.
2. Internal: `Agent(auditor)` with the spec, the absolute path of the diff,
   the repo path, and - on a re-audit - exactly what the previous round
   found, so it attacks the fix instead of re-reporting the bug. An
   internal pass is a claim too; it has returned zero findings on code an
   external audit then found major defects in.
3. External: invoke the `omp-fleet` skill, then one background Bash call per
   auditor, no `&`:

   ```
   exec $OMP_RUN audit-<topic>-<model-short> <workdir>/prompt.txt <model> 900
   ```

   Same prompt file for every external auditor, separate topics so the
   output directories differ. Read the report file, not the reply.
4. Arbitrate. For each finding, open the code and confirm the failure
   scenario. Verified findings are fixed (by `executor` or by you); the rest
   are recorded as rejected with one line why. Do not fix what you have not
   confirmed, and do not drop a finding because two auditors disagree.
5. Re-audit only the fix, with the previous findings in the prompt. Two
   rounds is the norm; a third means the spec was wrong, so stop and say so.
6. The commit body gets one line: `Audit: internal <verdict>, <model>
   <verdict>[, <model> <verdict>]; <n> findings fixed, <m> rejected.`

## Models

Pinned by direct name; aliases are remapped by the provider without notice.

| Role | Model |
|---|---|
| external, always | `google-antigravity/gemini-3.7-flash:high` |
| second external, risky variant | `synthetic/hf:zai-org/GLM-5.2:high` |
| never | `synthetic/syn:small:text:high` (fabricates findings; arbitrating a fabricated finding costs more than the audit saves) |

Never use a `syn:*` alias for an audit. Check `$OMP_RUN status` first if a
project of the operator's is running a live model on the same pool.

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
