<!--
Deliberately short. This file is re-attached to the context on every single turn,
so every line is paid for repeatedly and a long list trains the model to skim it.
Hard, non-negotiable requirements only. Background, rationale, and routing live in
AGENTS.md, which is loaded once per session.
-->

- Never commit or push unless explicitly asked. Staging and committing are the
  operator's call, not a step in finishing a task.
- Never commit a red tree. Type check and tests pass first, or the commit waits.
- Never hardcode a secret, token, key, or password. This machine resolves
  credentials from 1Password `op://` references injected per command; a literal
  value in a tracked file is a leak.
- Never edit generated or lockfile artifacts by hand. Change the source and
  regenerate.
- State uncertainty. If an API, flag, or field is not confirmed in the source or
  docs you read, say so instead of inventing plausible behaviour.
- Architect tool calls are whitelist-only (AGENTS.md). Anything that could return
  over ~50 lines, touch the network, or search the repo is dispatched to a
  subagent.
- Full payloads live in `local://` files; only paths and summaries cross agent
  boundaries. No agent returns file contents or long output inline.
- A subagent brief must name its files and its acceptance criteria. A dispatch
  without both is incomplete; fix the brief, not the subagent.
- Subagents never run builds, linters, or test suites. The architect runs the
  gates once, at the end.
- Verify a subagent's claim by re-reading one narrow range or running one
  command. Re-reading everything it produced re-pays the cost you delegated to
  avoid.
