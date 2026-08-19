---
name: oss-project-eval
description: Evaluates an open-source project, tool or technique against its own claims and produces a dated experiment record with measured numbers and an adopt/reject decision. Use this skill whenever the user points at a GitHub repository, a new tool, a benchmark result or a hyped technique and wants it looked at, tried, tested, benchmarked or compared - including casual framings like "is this any good", "should I use this", or "check out this repo".
compatibility: Needs a disposable execution environment (container or throwaway directory) for anything that runs the project's code.
---

# Open-source project evaluation

Turns "this looks interesting" into a record that can be re-read in two years:
what was claimed, what was measured, what was decided, and why.

## What failure this prevents

Adoption on the strength of a README. A project's own benchmark is designed by
the people who need it to win: it picks the workload, the baseline and the
metric. Accepting that number is `doctrine/00-invariants.md` Law 5 violated at
the tool level - the same self-verification failure that makes an agent's "done"
untrustworthy. The counter is not scepticism as an attitude but a measurement
against a baseline the evaluator chose.

The second failure it prevents: an evaluation that leaves no trace. Six months
later the only surviving artefact is a vague impression, so the same project
gets re-evaluated from zero.

## Procedure

This is `doctrine/05-adopting-new-terms.md` made executable. The five questions
there are the five phases here. Stopping early is a valid outcome and the common
one - most candidates die in phase 2.

### 1. Strip the claim

Read the README, the docs and the top-level source layout. Write the mechanism
in one sentence with the marketing removed. If that sentence cannot be written,
stop: what is not understood does not get measured, let alone adopted.

Then extract the claims as a table of **falsifiable** statements. "Blazing fast"
is not a claim; "3x faster than X on Y" is. Record which claims are untestable -
that fact is itself a finding.

Delegate the reading to a subagent (`Explore` for layout and provenance, a
general-purpose agent for the docs). A repository read into the main session
costs the rest of the session and buys a summary a subagent returns for a
fraction of it.

### 2. Which invariant does it serve

Name the one from `doctrine/05-adopting-new-terms.md` step 2: context economy,
verification, isolation, recovery, or cost/speed. If none of them, stop and
record the rejection - a one-line entry with a date is worth more than a
half-finished experiment.

Also answer the question most skipped: does this **replace** something already
in the system, or sit **next to** it? "Next to" needs a defence, because every
extra part carries maintenance cost forever.

### 3. Check provenance before running anything

Evaluating a project means running code written by strangers. Before that:

| Check | Why |
|---|---|
| Commit history, contributor count, last release | A one-author repo with three commits is a prototype, not a dependency |
| Install method | `curl \| sh` runs an unpinned remote script as you; prefer a pinned package or a container |
| Post-install hooks, network calls at import, telemetry | These run before any of your code does |
| What it wants access to | A tool asking for shell, credentials or the whole home directory has a blast radius wider than its job |

Run the project **in a container or a throwaway directory**, never on the host
working tree, and never with real credentials in the environment. Use scratch
data. This is Law 7 applied to third-party code: isolation is about damage, not
just context.

If the user asks to skip the sandbox, say what the exposure is once, then follow
their decision - it is their machine.

### 4. Measure against a baseline

An experiment without a control produces a number, not evidence. Define, before
running anything:

| Field | Rule |
|---|---|
| Hypothesis | Stated so a result can falsify it, not confirm it |
| Metric | Wall time, tokens, intervention count, pass rate - something countable |
| Baseline | The same task done the current way, measured in the same session |
| Workload | Your own task and your own data, not the project's demo |
| Repetitions | At least three runs where variance is plausible; report spread, not just the mean |

Record raw command output verbatim under `raw/`. A summarised measurement cannot
be re-checked later, and the summary is where the wishful thinking hides.

Two failure modes to watch, in this order:

- **A result that looks too good is a bug hypothesis before it is a finding.**
  Check for the trivial explanation first - warm cache, wrong baseline, work
  silently skipped, output not actually validated. Report both the finding and
  the check.
- **A result that is merely fine** still has to beat the cost of one more moving
  part in the system.

### 5. Decide and record

Every evaluation ends with one of: **adopt**, **reject**, **retry later**.
"Interesting, let's see" is not a decision and guarantees the work is repeated.

On adopt, the decision record names the concrete file under `workbench/agents/` that
changed and what it replaced. An adoption that changes no file did not happen.

## Output contract

One directory per evaluation:

```
lab/experiments/NNN-<project-slug>/
  EXPERIMENT.md      the record - copy assets/EXPERIMENT-template.md
  raw/               verbatim command output, one file per run
```

`NNN` continues the existing numbering in `lab/experiments/`, matching
`doctrine/05-adopting-new-terms.md`. The date lives in the record, not the
directory name, so the ordering on disk stays the order the work happened in.

Fill the tables. Per `CLAUDE.md` invariant 4, a narrative where a measurement
belongs teaches nothing later.

Anything the project produced that is bulky - logs, datasets, checkouts, build
output - stays out of the hub. Keep the numbers and the commands; drop the rest.
