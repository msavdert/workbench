# Operating model

The Synthetic pack is the scarce resource here (500 requests / 5h, one in-flight
request per model); the Antigravity OAuth quota is effectively unlimited by
comparison. Volume goes to Antigravity and the pack is spent only where depth
is worth paying for: you scope the work, decide the contracts, and verify the
result.

## Routing

| Work | Agent | Model |
|---|---|---|
| Scope, decompose, decide contracts, verify | you | `gemini-3.7-flash:high` |
| Escalate when stuck, or plan mode | you, via `slow` / `plan` | `syn:large:text` (`:max` / `:high`) |
| Find files, map unknown code, read-only search | `scout` | `gemini-3.7-flash:high` |
| Mechanical rename/move/reformat across files | `sonic` | `gemini-3.7-flash:high` |
| General multi-step implementation slice | `task` | `gemini-3.1-pro` |
| External library or API behaviour, from source | `librarian` | `Kimi-K3` |
| Write or rewrite documentation | `docs` | `Kimi-K3` |
| Adversarial review before "done" | `audit` | `GLM-5.2` |
| Second opinion on a diff | `reviewer` | `gemini-3.1-pro:high` |
| Repository vulnerability discovery, read-only | `security-reviewer` | `GLM-5.2` |
| UI/UX implementation and visual review | `designer` | `syn:small:vision` |

Synthetic allows one concurrent request **per model**. Different models never
contend; batch accordingly. Which ones are the same model is not obvious from
the names, because the aliases resolve to concrete models
(`references/benchmarks.md`, 2026-08-16): `syn:large:text` = GLM-5.2,
`syn:large:vision` = Kimi-K3, `syn:small:vision` = Qwen3.6-27B. So the real
contention map is:

- `librarian` and `docs` share the Kimi-K3 slot and serialize behind each other.
- `audit` and `security-reviewer` share the GLM-5.2 slot **with your own `slow`
  and `plan` roles**. An earlier version of this file claimed no subagent sits on
  the session's model; that was never true. It stopped being a per-turn problem
  on 2026-08-19, when the driver seat moved to Antigravity, but an audit fired
  during an escalation still queues behind it.
- `designer` shares `syn:small:vision` with the `vision` role. Both low-volume.

Everything else is on Antigravity, which is where the parallel width lives.

## Enforcement layer

`home/omp/hooks/pre/delegation.ts` hard-blocks the main session from network fetches and whole-file reads over 200 lines. It reaches `~/.omp/agent/hooks/pre/` because `home/install.sh` symlinks the whole `home/omp/hooks` directory there, and it fails open. (It used to say "via the Dockerfile COPY of `home/omp/`" - a leftover from the container predecessor; the box is a VM and nothing here is built into an image.) The ~50-line rule in the prose is the stricter judgement line the architect is expected to self-enforce well before the hook fires.

## The bright line

Every tool result you call lands in your context and is re-billed on every
subsequent turn for the rest of the session: a 300-line fetch on turn 3 is paid
for on turns 4 through 40. So the trigger is **output size, not difficulty**:

> If a tool call could return more than ~50 lines, fetches anything over the
> network, or searches the repo, it goes to a subagent. No exceptions — not for
> one curl, not for one grep, not for "I just need to check one flag."

Difficulty is irrelevant; payload size is what you pay for. Fetching a doc page
yourself to check one flag is the canonical anti-pattern: you needed a boolean,
you paid for a document, and you keep paying for it until the session ends.

### Your whitelist

Calls the architect is allowed to make directly:

1. Dispatching subagents (`task`) and messaging peers (`hub`).
2. Todo tracking.
3. Narrow ranged reads (an explicit line span under ~50 lines) to verify a
   specific claim or locate an edit anchor.
4. Single-fact shell commands: one file, one value, one short output (`ls`,
   `stat`, `git status`, checking one flag exists).
5. The final gates: `lsp diagnostics`, the project's check/test command,
   running the changed path, and reading diffs of files you did not write.

Anything not on this list is dispatched.

## Delegating

Fan out as wide as the work genuinely splits, in one batch. Subagent briefs,
output contracts, and batching mechanics live in `skill://delegation` — read it
when you orchestrate. Each brief carries its own file list and acceptance
criteria; subagents see none of this conversation. They never run gates; you do.

## Verifying

A subagent reporting success is a claim, not evidence. Verify by re-reading one
narrow range or running one command — never by re-reading everything the
subagent produced. Then the `audit` gate: read-only, adversarial, and nothing
is declared complete before it runs and its findings are fixed or explicitly
accepted.
