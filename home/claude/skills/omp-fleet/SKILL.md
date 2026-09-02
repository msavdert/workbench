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
| Second pool for demand research / verbatim quotes | `synthetic/hf:zai-org/GLM-5.2:high` - the DIRECT name, never the `syn:large:text` alias | 19/20 verbatim quotes; over word limits on summaries. Alias remapped without notice: `syn:large:text` resolves to GLM-5.3-Flash since ~2026-08-30, a live agentshard mind (see collision note) |
| Terse tables, one URL per row | `google-antigravity/gemini-3.1-pro:high` | Correct and minimal; narrower source use than flash |
| Overflow only | `synthetic/syn:large:vision:high` (Kimi-K3) | Faithful when it delivers, but 2.5-3.5x slower than flash and delivered 6 quotes in one run and 15 in the next |
| Never for web-facing work | `synthetic/syn:small:text:high` (GLM-4.7-Flash) | The only model that produced wrong facts and fabricated table rows |
| Never | Antigravity Anthropic models | Operator reserves that allowance |

**Synthetic aliases collide with a live system on this box.** The agentshard
shard runs part of its LLM cast on this same Synthetic subscription
(since window 25, 2026-08-30). As of window 43, 2026-09-02, only bruk is
left there: `hf:Qwen/Qwen3.8-27B` (= what `syn:small:vision` resolves
to). Ada is now OpenRouter `z-ai/glm-5.3-flash:floor` and doran the
Gemini API `gemini-3.5-flash-lite`; neither touches Synthetic, but a
fleet run must still avoid those two routes while the shard is up.
Beware `hf:zai-org/GLM-5.3-Flash` (= what `syn:large:text` NOW resolves
to): the same weights ada used to run, no longer a collision. Synthetic
allows **one request per model per subscription**; requests to different
models run in parallel. So a fleet run on any of those models - or on an
alias that silently remaps onto one, which Synthetic does without notice -
queues a live character behind it for as long as the run lasts, and at a
45 s timeout that means the character fails and stands still. While the
shard is up (`systemctl --user is-active agentshard-mind@bruk.service`),
name Synthetic models by DIRECT name only, use
`synthetic/hf:zai-org/GLM-5.2:high` as the Synthetic arm, and check the
live cast in `~/work/agentshard/ops/config/mind/*.llm.json` before naming
anything else.

**Synthetic auth (learned 2026-09-02).** omp stores its own copy of the
Synthetic API key in `~/.omp/agent/agent.db`, and that copy can go stale:
on 2026-09-02 every `synthetic/*` run got `401 Invalid API Key` and omp
walked its configured fallback chain (`retry.fallbackChains` in
`config.yml`) onto the Google pool without saying so - a run launched as
GLM-5.2 was answered by gemini-3.1-pro. The wrapper now resolves the key
from `op://dotfiles/Synthetic/credential` per run for `synthetic/*` models
and passes it with `--api-key` (override by exporting `OMP_API_KEY`; a
failed `op read` is written to `research/_work/<topic>/warnings.log` as
well as stderr, and `status` masks the key in argv). Two
consequences: (1) **before crediting any model, read the run's omp log**
(`~/.omp/logs/omp.<date>.<pid>.log`) for `"provider":"..."` lines and
"agent turn ended with provider error"; a clean `run.log` proves nothing
about which model answered; (2) the Synthetic docs warn that pinned model
names can 404 when a model is rotated out - that is a different failure
from this 401. Keep the direct names (the alias remap onto a live cast
model is the worse risk); if a pinned name ever 404s, re-pin to the
current name from https://dev.synthetic.new/docs/api/models.

Pick from this table; do not re-derive the choice from the benchmark history.
Every model here can ship a wrong figure, so the model choice never removes
rule 8. Evidence and history: `references/benchmarks.md`.

## Hard rules

Each rule exists because its absence has already cost real quota or a real
result; the incidents are in `references/operations.md`.

0. **Check search works before launching - but only for runs that will
   search the web.** Run it as `timeout 30 omp search --provider=mojeek
   "<any query>"`. It returns the provider and result count in about one
   second. Do NOT run the bare `omp search "<q>"`: in its default form the
   command prints its results and then never exits (measured 2026-09-02: a
   foreground call blocked the session for the full tool timeout with the
   results already on screen). A run whose search silently fails is not a
   slow run, it is a discarded one - see the fabrication incident in
   `references/operations.md`. `--provider=<name>` switches provider if
   Mojeek is down. File-only delegates (audits, extraction from local files)
   do not need this check at all. Note this is `omp`'s own search, which
   egresses from this box; a Claude Code session's `WebSearch` runs on
   Anthropic infrastructure and is unaffected by anything that blocks the
   box, so the two can disagree.
1. **Always run in the background, as ONE Bash call per run, with no trailing
   `&`.** Research takes 5-15 minutes; the Bash tool caps at 10 and a foreground
   kill wastes the run. The exact shape:

       Bash(run_in_background: true,
            command: "exec ~/.claude/skills/omp-fleet/omp-run.sh <topic> <abs-prompt-path> <model> <seconds>")

   The harness already detaches it. An extra `&` inside that call puts the
   wrapper in a child process group that dies when the outer command exits, and
   the run is gone seconds after it starts.

1a. **Liveness is process CPU. `$OMP_RUN status` and `run.log` are not.**
   `status` has reported "none" while two runs were working, and `run.log`
   stays at 11 bytes until the run exits because `omp -p` buffers. Do not
   relaunch on either signal - you get two runs racing on one output file.
   Check `ps -eo pid,etime,time,args --no-headers | grep '[o]mp -p --model'`
   for growing etime and non-zero CPU, and `pgrep -af "omp-run.sh <topic>"`
   before relaunching anything. Details and the kill-cascade trap are in
   `references/operations.md`.
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

**Write the prompt file with the harness Write tool, never a shell
heredoc.** Measured 2026-08-28: a Claude Code session's sandboxed foreground
shell held a `cat > ... <<'PROMPT'` write in an overlay the detached
background run could not see - two launches died with "prompt file not
found" while a foreground `ls` showed the file. The Write tool writes
through the harness to the real filesystem (and creates the directory);
shell heredocs only look equivalent. The same divergence runs the other
way: a foreground `ls`/`find` can lag files the background run wrote, so
verify outputs with the Read tool or a `run_in_background` `ls`, never
conclude from the foreground view alone.

```
Write(file_path: <abs-repo>/research/_work/<topic>/prompt.txt, content: <template below>)
Bash(run_in_background: true,
     command: "exec $OMP_RUN <topic> <abs-repo>/research/_work/<topic>/prompt.txt [model] [max-seconds]")
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

OUTPUT: Write the full report to <ABSOLUTE path:
/...repo.../research/_work/<topic>/<outfile>.md>. Then reply with AT MOST 5
lines: what you found, how many sourced figures, and anything you failed to
get. Nothing else.
```

Give the output path ABSOLUTE, always. The wrapper runs the delegate with
the topic dir as its cwd, but a delegate handed "./report.md in the current
directory" has still re-derived a repo-relative path from context and nested
it under `research/_work/<topic>/research/_work/<topic>/` (2026-08-28). If
the file is not where you asked, `find` the topic dir (in a background call)
before declaring the run lost - so far the report has always existed.

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
