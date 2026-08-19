# Overnight Autonomous Run — Protocol

Project-agnostic. Copy into a project and fill in the project-specific slots.

**Read this first:** the target is not "run for 8 hours". The target is to
extend the measured autonomy horizon (`doctrine/00-invariants.md` Yasa 8) by
closing one failure class at a time. A system that cannot survive 30 unattended
minutes will not survive 8 hours; it will just fail later and more expensively.

Every run is logged in `lab/runs/`. A run without a log is not an experiment.

---

## Preconditions — all must hold before starting a run

- [ ] **A verification command exists** and is fast enough to run per step.
      Without it there is no loop, only drift (Yasa 5).
- [ ] **The goal is bounded.** A concrete backlog of items, each with its own
      done-condition. Not "finish the project" — that invites scope invention.
- [ ] **The plan was reviewed by a human** before the run started. Plan mode
      output, approved. The agent does not get to invent the plan overnight.
- [ ] **Irreversible actions are denied** (see denylist below).
- [ ] **Blast radius is bounded** — disposable container, mounted paths only.
- [ ] **The tree is clean** and on a dedicated branch, not the default branch.
- [ ] **A time or token ceiling is set** at the harness level, not as prose.
      A model asked to "stop after a while" will not.

---

## During the run — required agent behaviour

**Checkpoint discipline.** Commit after each backlog item whose verification
passes. Never one giant commit at the end. If the agent goes off the rails at
03:00, you must be able to return to the last *verified* state — and you can
only do that if verified states were recorded.

**Verification gate.** An item is done only when its verification command
passes. If verification fails twice in a row on the same item, stop working on
it, log a blocker, move to the next independent item. Do not keep retrying —
that is where token budgets die.

**Blocker protocol — do not wake the operator.** When stuck, append to
`BLOCKERS.md` and move on:

```
## <ISO timestamp> — <backlog item>
What I was doing:
What went wrong (exact error/output):
What I tried:
What I need from you (a decision? a credential? a clarification?):
State I left behind: <branch, last good commit>
```

The operator reads this in the morning, in one pass. This costs the agent a few
tokens and saves the operator a night.

**Scope discipline.** Deliver the backlog at the scope it was written. If you
believe an item is wrong or a better approach exists, write it in
`BLOCKERS.md` and continue with the item as specified. Do not silently widen,
narrow, or transform it.

**Honest reporting.** If tests fail, say so with output. If an item was skipped,
say so. Never report an item complete because it looks complete — verification
is what makes it complete.

**Context hygiene.** Delegate anything that returns large output to a subagent.
A long unattended run is exactly the case where context overflow degrades
coherence, and it degrades quietly (Yasa 2, 3, 7).

---

## Denylist — forbidden without human approval in the same session

Baseline for every project:

- `git push --force`, history rewrite, branch deletion
- Anything targeting the default branch
- Database migrations against anything but a disposable local instance
- Deploys to any shared or production environment
- Outbound messages: email, Slack, webhooks, API calls that write to a third party
- Package publication, release tagging
- Credential creation, rotation, or deletion
- Deleting files not created during this run
- Disabling, weakening, or skipping any test — including "temporarily"

Project-specific additions go here. For quantitative research, see
`agents/templates/quant-research/INTEGRITY.md` Part 3 — that list is
stricter and it overrides this one where they overlap.

---

## Morning review — 15 minutes, in this order

1. **`BLOCKERS.md` first.** Before any code. It tells you where the ceiling is.
2. **Verification state.** Does the suite pass on the final commit?
3. **Read the diff of what you did not write.** Not every line — the parts that
   touch anything load-bearing.
4. **Fill in `lab/runs/YYYY-MM-DD-<name>.md`.** Especially: time to first
   intervention, and the class of every intervention.
5. **Pick exactly one structural change** for the next run, targeting the most
   frequent intervention class. One change per run, so effects attribute.

---

## Ramp — do not skip steps

| Stage | Target duration | Move on when |
|---|---|---|
| 1 | 30 min | two consecutive runs, zero interventions |
| 2 | 2 hours | two consecutive runs, zero interventions |
| 3 | 4 hours | two consecutive runs, ≤1 intervention |
| 4 | overnight | two consecutive runs, ≤1 intervention, no denylist hits |

Each stage teaches you a different failure class. Jumping to stage 4 does not
save time; it produces one expensive, uninterpretable failure instead of four
cheap, informative ones.
