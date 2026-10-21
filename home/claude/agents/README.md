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
makes every design decision. Subagents never carry design judgment; all
but `executor` run on the `sonnet` alias, so the architect's usage budget
is spent on thinking and the delegates still get a capable model.
`executor` runs on the `opus` alias because it writes the code that
ships. Effort follows the work: `high` where the agent edits or judges,
`medium` where it only retrieves or runs commands. No agent runs at
`low`.
The aliases follow the newest Sonnet and Opus (assumption, not verified
here; no `ANTHROPIC_DEFAULT_SONNET_MODEL` or `ANTHROPIC_DEFAULT_OPUS_MODEL`
pin is set in this repository).

| Agent        | Justification        | Model  | Effort | Tools            | Returns                          |
|--------------|----------------------|--------|--------|------------------|----------------------------------|
| `explore`    | isolation (reads)    | sonnet | medium | read-only        | locations as `file:line`         |
| `grunt`      | isolation (logs)     | sonnet | medium | all but Agent    | exit codes, extracted failures   |
| `executor`   | isolation (edits)    | opus   | high   | all but Agent    | delivered paths + verification   |
| `auditor`    | isolation (fresh eye)| sonnet | high   | read-only        | verdict + defensible findings    |
| `researcher` | isolation (network)  | sonnet | medium | web + read-only  | sourced summary, no raw pages    |

Rules that follow from the table:

- A subagent's model is never `inherit` or `fable`. If a task needs the
  architect's model, it is architecture and belongs in the main session.
- `executor` is `opus` at high (operator decision 2026-10-21, reported
  rather than measured); every other agent is `sonnet` (operator decision
  2026-10-01); effort is `high` for `executor` and `auditor`, `medium` for
  `explore`, `grunt` and `researcher` (operator decision 2026-10-21: no
  `low` anywhere; from 2026-10-01 to then they ran at `low`, after a first
  pass that put all five on high). Before 2026-10-01, `executor` ran on
  opus at medium, `researcher` on sonnet at medium, and `explore`,
  `grunt` on haiku at low; the opus choice dated from 2026-09-01 and was
  based on the operator's daily use, reported rather than measured. If a
  stronger model or more effort for any agent is ever warranted, measure
  it and report the result in the session (earlier experiment records
  are in the archived `vault` repository,
  `50-knowledge/ai/experiments/`).
- No delegate spawns delegates. `executor` and `grunt` have
  `disallowedTools: Agent`, and `auditor`, `explore` and `researcher` have
  allowlists without it, so none can start its own chain; one delegate
  is one process, and the architect decides when an audit happens (the
  `audit` skill).
- `explore` is lowercase on purpose (operator decision 2026-10-01), so it
  does not override the built-in `Explore`; both exist and callers must
  ask for `explore` by name. Names are matched case-sensitively
  (assumption, not verified here).
- Read-only agents get an explicit `tools:` allowlist. Agents that must
  write get no list, because a stale allowlist silently breaks them when
  the harness renames a tool.
- The read-only allowlists of `explore` and `auditor` include `Bash`
  (for `git log`, `git grep`, running existing tests). The harness does
  not restrict what that Bash runs; read-only is enforced by the prompt
  only. This is a deliberate trade: without `Bash` both agents lose git
  history and test runs.
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
archived `vault` repository, `50-knowledge/ai/journal/2026-08-06-transkript-bulgulari.md`.
`executor` and `auditor` were lifted from the agentshard project on
2026-09-02, where they replaced the same builder/reviewer loop.
