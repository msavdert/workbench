---
name: omp-fleet
description: Delegate large-output work (web research, bulk extraction, document summarization, long drafts) to local `omp` CLI agents running on separate AI subscriptions, so the work does not consume Claude Code session limits. Use whenever a task would pull more than ~2k tokens of material into context, or would burn Claude subagent tokens on retrieval rather than judgment.
---

# omp-fleet - delegating work off the Claude quota

A Claude subagent bills its whole token usage to the operator's Claude limit.
The same machine has `omp` authenticated against two other subscriptions.
Work routed through `omp` costs this session only the short summary that comes
back. This is quota arbitrage, not a quality upgrade: the delegated models are
weaker than the one running this session. Route retrieval and bulk work to
them; keep judgment here.

## What to delegate, what to keep

| Delegate | Keep in this session |
|---|---|
| Multi-source web research, enumeration, extraction, reformatting, first drafts of reference material | Strategy, decisions, decision records, roadmap, the project's state and handoff files - anything that says what the findings mean |

## Model policy

Measured in `lab/experiments/010-omp-fleet-delegate-models/` (factual research,
extraction, summaries) and `011-omp-fleet-demand-research/` (verbatim quotes
from forums under source rules), both 2026-08-16. Synthetic models are named
by alias as the vendor recommends; what each alias resolves to is recorded in
`references/benchmarks.md`.

| Task | Model | Why |
|---|---|---|
| Default for every delegated task: research with citations, demand research with quotes, extraction, summaries | `google-antigravity/gemini-3.7-flash:high` | As accurate as any model measured on facts, 18/18 verbatim quotes in both demand-research runs, uses all allowed source types, fastest, and the Google pool is the least loaded |
| Second pool for facts, extraction, summaries | `synthetic/syn:small:vision:high` (**Qwen3.8-27B since ~2026-08-27; benchmarked as Qwen3.6-27B**) | Same accuracy on facts, respects limits; but 7 of 16 quotes were near-verbatim, not verbatim - not for quote work. **Do not use while the agentshard shard is running: see the collision note below.** |
| Second pool for demand research / verbatim quotes | `synthetic/syn:large:text:high` (GLM-5.2) | 19/20 verbatim quotes; over word limits on summaries |
| Terse tables, one URL per row | `google-antigravity/gemini-3.1-pro:high` | Correct and minimal; narrower source use than flash |
| Overflow only | `synthetic/syn:large:vision:high` (Kimi-K3) | Faithful when it delivers, but 2.5-3.5x slower than flash and delivered 6 quotes in one run and 15 in the next |
| Never for web-facing work | `synthetic/syn:small:text:high` (GLM-4.7-Flash) | The only model that produced wrong facts and fabricated table rows |
| Never | Antigravity Anthropic models | Operator reserves that allowance |

**`syn:small:vision` collides with a live system on this box.** The agentshard
shard runs an LLM-driven character (`bruk`) on `hf:Qwen/Qwen3.8-27B`, which is
what `syn:small:vision` now resolves to, on this same Synthetic subscription.
Synthetic allows **one request per model per subscription**; requests to
different models run in parallel. So a fleet run on `syn:small:vision` queues a
live character behind it for as long as the run lasts, and at his 45 s timeout
that means he fails and stands still. Use `syn:large:text:high` as the Synthetic
arm instead while that shard is up. Check with
`systemctl --user is-active agentshard-mind@bruk.service`.

Pick from this table; do not re-derive the choice from the benchmark history.
Every model here can ship a wrong figure, so the model choice never removes
rule 8. Evidence and history: `references/benchmarks.md`.

## Hard rules

Each rule exists because its absence has already cost real quota or a real
result; the incidents are in `references/operations.md`.

0. **Check search works before launching.** `omp search "<any query>"` returns
   its provider and result count in seconds. A run whose search silently fails
   is not a slow run, it is a discarded one - see the fabrication incident in
   `references/operations.md`. `omp search --provider=<name>` switches provider
   if the default is down. Confirmed working 2026-08-27 via Mojeek. Note this
   is `omp`'s own search, which egresses from this box; a Claude Code session's
   `WebSearch` runs on Anthropic infrastructure and is unaffected by anything
   that blocks the box, so the two can disagree.
1. **Always run in the background** (`run_in_background: true`). Research takes
   5-15 minutes; the Bash tool caps at 10 and a foreground kill wastes the run.
2. **The delegate writes to a file and replies in at most five lines.** If
   findings come back as prose, the token saving that justifies the mechanism
   is gone.
3. **Name the built-in `web_search` tool and forbid scrapers, Playwright and
   hand-written fetchers.** Left unprompted, delegates spend the run writing
   scrapers and return empty files.
4. **Run in an isolated work directory** (`research/_work/<topic>/`).
   Delegates leave debris.
5. **Never delegate judgment.** See the table above.
6. **One delegate is one process - forbid the `task` tool and subagents in the
   prompt.** Children spawned by omp's worker daemon outlive a dead parent and
   have drained a full day of quota on both pools. The wrapper also strips
   `task` from the allowlist; the prompt says it again because the wrapper is
   the last line, not the first.
7. **Check quota before writing the prompt:** `$OMP_RUN status`.
8. **Verify before promoting.** Delegate output is a claim, not a finding.
   Before a number reaches a decision: open the source and read the figure
   yourself, and **recompute every derived number** (products, sums,
   per-year totals) from its inputs - delegates have shipped tables whose
   own arithmetic does not hold, and readers copy them. Do not trust
   self-rated confidence; a "HIGH" on n=6 is thin, say so.
9. **Check who wrote each source, not just that a URL exists.** For anything
   about what people want, believe or pay, add the SOURCE RULES block below;
   without it you get vendor marketing back, and marketing always agrees
   with the hypothesis.

## Invocation

Resolve the wrapper once per session, project-local copy first:

```bash
OMP_RUN=./tools/omp-run.sh
[ -x "$OMP_RUN" ] || OMP_RUN=~/.claude/skills/omp-fleet/omp-run.sh
```

Always launch through `$OMP_RUN`; never call `omp` directly. The wrapper
carries the tool allowlist, the quota gate and the orphan reaper (internals in
`references/operations.md`). It treats the current directory as the project
root; override with `OMP_PROJECT_ROOT`.

```bash
cd <repo-root>                       # same command as the launch: an earlier cd poisons $REPO
mkdir -p research/_work/<topic>
cat > research/_work/<topic>/prompt.txt <<'PROMPT'
<the prompt, from the template below>
PROMPT
$OMP_RUN <topic> "$PWD/research/_work/<topic>/prompt.txt" [model] [max-seconds]
```

Rules that bite here: the prompt path is **absolute**; the launch is
backgrounded (rule 1); do not pipe the launch through `tail` - you would read
`tail`'s exit code, not the wrapper's. Defaults: model per the policy table,
900 seconds. `$OMP_RUN status` shows running agents and quota; `$OMP_RUN reap`
kills every stray agent now.

For fan-out across pools, launch separate top-level runs from this session
with `&` and `wait`, one output file each - never let a delegate fan out.

## Prompt template

```
<the research or extraction task, stated concretely>

TOOLS: Use your built-in web_search tool for searching. Do NOT launch
subagents and do NOT use the task tool - you are a single process and
parallelism here drains a shared quota. Do NOT write your own scraper, do NOT
use Playwright, do NOT write Python to fetch pages. If web_search fails twice
on the same query, record the failure in the report and move on.

If search is unavailable, say so and return a short report. Do NOT answer from
your own knowledge and present it as retrieved material. Every claim must come
from a page fetched during THIS run and must carry the URL it came from. A
short sourced report is a success; a long unsourced one is a discarded run.

RULES:
- Every number, quote, and claim gets a source URL.
- If you cannot source something, label it ESTIMATE. Never present an
  inference as a finding.
- Prefer <date range> sources; note the date of each figure.
- Markdown tables for anything comparative.
- No advice, no encouragement, no padding. Findings only.
- End with a CONFIDENCE section: which findings are well-sourced, which are
  thin, and what you could not find.

OUTPUT: Write the full report to ./<outfile>.md in the current directory.
Then reply with AT MOST 5 lines: what you found, how many sourced figures,
and anything you failed to get. Nothing else.
```

### SOURCE RULES block - add verbatim for demand research

```
SOURCE RULES - these override the search results' apparent relevance:
- Acceptable: forum and discussion posts written by the person themselves -
  Reddit, Hacker News comments, Blind, Stack Overflow Meta, mailing lists.
- Banned as evidence: any page published by a company that sells a product in
  this space, including its blog, landing page, case studies, testimonials, and
  "ultimate guide" content marketing. dev.to and Medium posts are banned unless
  the author is clearly an individual describing their own experience.
- Banned: comments on a product's own launch or announcement thread. They are
  testimonials, not complaints.
- For every quote, state in one clause WHO is speaking and WHY they posted -
  e.g. "engineer asking for help, unprompted" versus "vendor describing a
  prospect". If you cannot establish that, drop the quote.
- A quote that reads as second person ("You can explain a system design...") is
  marketing copy addressed at a reader. It is never evidence. Discard it.
- Report the real distribution even if it is boring or contradicts the premise.
  Under-delivering on quote count is correct; padding with vendor copy is not.
```

## After the run

1. Read only the head of the output file first; a bad run should cost 200
   tokens to reject, not 3,000.
2. Apply rule 8: open sources for decision-relevant figures, recompute derived
   numbers, check source authorship (rule 9).
3. Merge only the verified parts into the project's proper files; the raw
   file stays under `research/` as provenance.
4. Note in the project's log or handoff file what was delegated and whether it
   landed. A delegated job that dies silently is the failure that has cost a
   full research pass.

## When something looks wrong

Before killing a run, or when a launch misbehaves, read
`references/operations.md`: how to tell a live run from a hung one (the log
and the quota bar are not the signal; process CPU is), and the failure-mode
table with fixes.
