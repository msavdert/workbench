# Subagent authoring conventions

Applies to every agent definition in this directory. Before adding a new
one, check that it's actually justified — a subagent is not the default
decomposition unit.

## When a subagent is justified

Only two cases:

1. **Parallelization** — the same kind of work needs to run across many
   instances at once (research, codebase exploration across independent
   areas).
2. **Isolation** — the task genuinely needs a fresh, uncontaminated
   context to do its job right, not the orchestrator's accumulated
   history. Code review is the canonical case: a reviewer that inherited
   the implementer's context will rationalize the implementer's choices
   instead of catching them.

If a task doesn't need either property, it stays in the main
conversation or becomes a skill instead — see `../skills/README.md`.

## Roster and model policy

The main session is the architect: it runs on the strongest model at
high effort (`model` and `effortLevel` in `~/.claude/settings.json`) and
makes every design decision. Subagents never carry design judgment; they
run on cheaper models so the architect's usage budget is spent on
thinking, not on retrieval or mechanical edits.

| Agent        | Justification        | Model  | Effort | Tools            | Returns                          |
|--------------|----------------------|--------|--------|------------------|----------------------------------|
| `Explore`    | isolation (reads)    | haiku  | low    | read-only        | locations as `file:line`         |
| `grunt`      | isolation (logs)     | haiku  | low    | all              | exit codes, extracted failures   |
| `executor`   | isolation (edits)    | opus   | medium | all but Agent    | delivered paths + verification   |
| `auditor`    | isolation (fresh eye)| sonnet | high   | read-only        | verdict + defensible findings    |
| `researcher` | isolation (network)  | sonnet | medium | web + read-only  | sourced summary, no raw pages    |

Rules that follow from the table:

- A subagent's model is never `inherit` or `fable`. If a task needs the
  architect's model, it is architecture and belongs in the main session.
- `executor` is the one agent on `opus`. The earlier rule (no agent on
  opus, the budget belongs to the architect) was overturned by the
  operator's daily use through 2026-09-01, reported rather than measured:
  a sonnet `builder` whose work went through about three audit rounds per
  task cost more usage and more architect attention than one opus run
  that passes audit, and the same contract on opus in agentshard did not
  show the loop. If a measurement is ever taken, record it in the vault's
  `50-knowledge/ai/experiments/`.
  `auditor` stays on sonnet; if it misses defects a stronger model
  catches (measure, do not assume), raise it - one line, and record the
  measurement in the vault's `50-knowledge/ai/experiments/`.
- No delegate spawns delegates. `executor` has `disallowedTools: Agent`
  and `auditor` has a read-only allowlist, so neither can start its own
  review chain; one delegate is one process, and the architect decides
  when an audit happens (the `audit` skill).
- `Explore` overrides the built-in agent of the same name (user-level
  `~/.claude/agents/` beats plugin definitions; project `.claude/agents/`
  beats both). Keep the name's capitalization so the override holds.
- Read-only agents get an explicit `tools:` allowlist. Agents that must
  write get no list, because a stale allowlist silently breaks them when
  the harness renames a tool.
- Every description says when *not* to use the agent. Auto-delegation
  keys on the description, and a description without a negative boundary
  causes over-delegation.
- Bulk retrieval that would exceed a single agent's read goes to the
  `omp-fleet` skill (separate subscriptions), not to `researcher`.

Deployment: `~/.claude/agents` is a symlink to this directory, so a file
saved here is visible to every Claude Code session without a copy step.
Verify with `ls -la ~/.claude/agents`.

## Anti-pattern: subagent wrapped as a callable tool

Don't expose a subagent as a tool the orchestrator calls mid-turn and
expects a synchronous, structured return from. That shape causes
orchestrator↔subagent communication breakdowns — the orchestrator can't
distinguish "subagent succeeded with this exact output" from "subagent
misunderstood the tool contract." Subagents report back in prose for a
human/model to read, not in a schema a caller depends on.

---
Source: Anthropic Applied AI talk "Tool, skill, or subagent: Decomposing
an agent" (analyzed 2026-08-06). Full findings:
vault `50-knowledge/ai/journal/2026-08-06-transkript-bulgulari.md`.
`executor` and `auditor` were lifted from the agentshard project on
2026-09-02, where they replaced the same builder/reviewer loop.
