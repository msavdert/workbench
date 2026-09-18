---
name: audit
description: Pre-commit internal audit of changes using a dedicated read-only auditor subagent running on Gemini 3.8 Flash (High). Use before any commit the operator asked for, when the operator says "audit", "denetle", "review before commit", or when completing a substantial change.
---

# audit (Antigravity Internal Subagent)

Pre-commit code and configuration audit performed by an internal read-only
`auditor` subagent with fresh context, running on **Gemini 3.8 Flash (High)**.
The primary agent (architect) orchestrates the audit, inspects the code to
verify each finding, fixes real defects, and explains rejections.

## Model Configuration

- **Auditor Model:** `Gemini 3.8 Flash (High)`
- **Tool Access:** Strictly read-only (`enable_write_tools: false`, `enable_subagent_tools: false`)
- **Reasoning Effort:** High

## Procedure

### 1. Scope and Diff Preparation

1. Inspect modified files and gather the exact diff:
   - For unstaged/staged changes: `git diff HEAD` (or `git diff --cached`)
   - For specific commits: `git diff <base>..<head>`
2. Identify the original specification / requirement:
   - What did the user or plan ask for?
   - What decisions or files govern this change?
3. If the diff is empty, stop and inform the user that there are no changes to audit.

### 2. Define and Invoke the Auditor Subagent

Define the internal auditor subagent using `define_subagent` (if not already defined in this conversation):

```json
{
  "name": "auditor",
  "description": "Adversarial read-only code auditor for pre-commit verification running on Gemini 3.8 Flash (High)",
  "enable_write_tools": false,
  "enable_subagent_tools": false,
  "enable_mcp_tools": false,
  "system_prompt": "You are an adversarial internal code auditor explicitly pinned to Gemini 3.8 Flash (High). Assume the change is broken and try to prove it. You are strictly read-only: never propose code edits, never mutate the repository. Your task is to audit the provided diff against the original requirement.\n\nAudit categories in order of severity:\n1. Correctness bugs: concrete input/state, failure scenario, and wrong outcome. Every bug must include a reproducible failure scenario.\n2. Spec drift: what was asked vs what was actually delivered, including silently skipped or incomplete requirements.\n3. Dishonest claims: assertions in docstrings, commit logs, or reports that the code or filesystem state does not back up.\n4. Security & Safety: hardcoded secrets, injection vectors, unsafe permissions, unexpected side effects.\n5. Repository invariants: idempotency, single-source rules, no emoji, documentation moving with code.\n\nFormat your report as follows:\n- Summary: brief overview of changes audited\n- Findings: list each finding with file:line, severity (Critical, Major, Minor), failure scenario, and explanation\n- Verdict: pass | pass with findings | fail\nIf findings are empty, explicitly state what files and scenarios you checked to earn that verdict.\n\nCOMMUNICATION PROTOCOL: When your audit is complete, you MUST use the send_message tool to send your full Markdown report and verdict back to the calling orchestrator conversation ID."
}
```

Invoke the subagent using `invoke_subagent`:

```json
{
  "Subagents": [
    {
      "TypeName": "auditor",
      "Role": "Adversarial Code Auditor",
      "Model": "flash",
      "Workspace": "inherit",
      "Prompt": "Audit the following change.\n\nSPEC (what was requested):\n<Insert user request or task description>\n\nDIFF TO AUDIT:\n<Insert git diff output or file paths to inspect>\n\nInspect the source files using view_file and grep_search. When done, transmit your full audit findings and verdict to the calling orchestrator using send_message."
    }
  ]
}
```

*Auditor Model:* Pinned explicitly to **`Gemini 3.8 Flash (High)`** (via `"Model": "flash"` with high reasoning effort).

### 3. Arbitration (Verification by Primary Agent)

The primary agent must arbitrate every finding:
1. **Treat findings as claims, not facts:** Open the relevant file and examine the code to see if the failure scenario actually occurs.
2. **Fix verified defects:** Apply fixes for all confirmed bugs or omissions.
3. **Reject false findings:** If a finding is a false positive or misunderstands the context, explicitly record why it was rejected.
4. If major fixes were applied, run a second audit pass focusing only on the newly modified lines.

### 4. Audit Reporting and Commit Integration

Report the audit outcome to the user:
- State the auditor model: **Gemini 3.8 Flash (High)**
- List verified findings and the fixes applied
- List rejected findings with rationale
- Report the final verdict (`pass`, `pass with findings`, or `fail`)

When writing a commit message (if asked to commit), include the audit record:
`Audit: internal auditor (Gemini 3.8 Flash (High)) <verdict>; <n> findings fixed, <m> rejected.`
