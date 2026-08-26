---
name: delegation
description: Use when acting as the architect orchestrating subagents - dispatching tasks, writing briefs, batching parallel work, enforcing the output-size bright line, and verifying subagent results without re-reading their payloads.
---

# Delegation

The mechanics behind the bright line in `home/omp/AGENTS.md`: how to brief,
how to batch, what a subagent must return, and why the cost model makes inline
bulk I/O the failure mode.

## Why the bright line exists

Context is charged per turn. Everything in the conversation — every past tool
result included — is re-sent to the model on every new turn. A 300-line tool
result you pulled on turn 3 is billed again on turns 4, 5, ... 40. The fetch
itself was cheap; the rent is not.

This is why difficulty is the wrong trigger. "It is only one curl" fetches a
whole page to answer one question, and that page occupies Opus context for the
rest of the session. The correct test is output size:

- Could return more than ~50 lines -> subagent.
- Fetches anything over the network -> subagent.
- Searches the repo (grep/glob/find across many files) -> subagent.

A subagent on a cheap model absorbs the large payload in *its* context, throws
it away, and returns the small answer. Only the small answer crosses into your
context, and only the small answer is re-billed.

Prompt caching discounts re-sent *prefixes* (~90%), which is why the system
prompt must stay stable and small — but tool results land mid-conversation,
after which the cache stops matching. Payloads inline are paid at full rate.

## Writing a brief

A subagent sees none of your conversation. The brief is its whole world, so it
must contain:

1. **Target files.** An explicit list of paths it owns or reads. "Look around"
   is not a file list.
2. **Contract.** What must be true when it finishes, stated so you can check it
   mechanically: the edit to make, the field to report, the answer to return.
3. **Acceptance criteria.** Observable outcomes, not effort. "The import path
   compiles under `tsc`" not "make the imports right".
4. **Constraints.** No gates: no builds, linters, formatters, or test suites —
   the architect runs them once at the end. No committing. No touching files
   outside its target list.
5. **Output contract.** See below.

Bad brief (everything wrong):

> Look into the auth module and clean it up.

Good brief (same work):

> In `src/auth/`, rename the exported `verify` function to `verifyToken` in
> `src/auth/verify.ts` and update its three call sites in
> `src/auth/session.ts`, `src/routes/login.ts`, and `src/middleware/guard.ts`.
> Touch no other files. Do not run tests or builds. Acceptance: no remaining
> references to the old name; signatures otherwise unchanged.

## Output contract

Subagents return at most ~15 lines plus file paths. Never full content.

- Bulk output (generated docs, research findings, long diffs, logs) is written
  to a `local://` file; the subagent returns the path and a summary.
- Summaries never paste file contents, web page bodies, or command output over
  ~10 lines.
- A `files` list carries `path` + one-line description per file changed.
- Uncertainty is stated, not smoothed over: unverified claims are listed
  explicitly (`unverified` field in the `task` agent's output schema).

Only paths and summaries cross agent boundaries. If you need the content, read
a narrow range of the file — you are paying for that range, not for the
payload.

## Batching

Fan out as wide as the work genuinely splits, in one batch — not one task at a
time while you watch. `task.maxConcurrency` caps the batch; within it, model
contention decides what actually runs in parallel.

Synthetic allows one concurrent request **per model**. Two subagents on the
same Synthetic model serialize; different models run in parallel. Today:
`audit` (GLM-5.2) parallelises with anything, while `librarian` and `docs`
share the Kimi-K3 slot and must not be dispatched simultaneously. Check
`home/omp/config.yml` `task.agentModelOverrides` before batching.

Independent slices go in one dispatch message so they start together. Dependent
slices (B needs A's output) are separate waves — name the dependency in B's
brief and pass A's result paths forward.

Do not poll or loop on running tasks. When a batch is dispatched, yield the
turn immediately. The harness delivers completed tasks asynchronously via
`<system-notice>` at zero token cost while the agents run.

## Verifying

A subagent's success report is a claim, not evidence. Verification is cheap and
targeted:

- Re-read **one narrow range** to confirm the specific claim that matters — a
  renamed symbol, an inserted block. Never re-read the whole file.
- Run **one command** for a behavioural check.
- Read diffs of files you did not write, not their full contents.
- Then the gates, once: `lsp diagnostics`, the project's check/test command,
  exercising the changed path. Subagents never run these — half-finished
  parallel edits would make them block on each other.

## Anti-patterns

| You were tempted to | Do instead |
|---|---|
| Fetch a doc page to check one flag | Dispatch `librarian` to return the flag's behaviour |
| Run one grep to find a call site | Dispatch `scout` to return the call-site list |
| Curl an API to see one field | Subagent fetches, writes body to `local://`, returns the field |
| Re-read a subagent's full output file | Read the narrow range that covers its claim |
| Run the test suite after each subagent finishes | Gates once, at the end, after the batch settles |
| Poll `hub(op="wait")` waiting for a subagent | Yield the turn immediately; harness auto-delivers completions via `<system-notice>` |
