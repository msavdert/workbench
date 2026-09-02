<!--
Deployed to ~/.claude/CLAUDE.md — loaded into EVERY Claude Code session, in
every project, and re-sent on every turn. Each line here is paid for repeatedly
and a long list trains the model to skim it. Hard operator preferences only.
Rationale belongs in the vault (50-knowledge/ai/doctrine/), not here. If this file grows past ~30
lines, something in it belongs somewhere else. Admission test: would the model
derive this from the repo, or already do it by default? If yes, leave it out.
-->

# Operator preferences

- Read narrowly: a line range, not a whole file. Locate the range with `grep`
  or an LSP symbol lookup first.
- Anything that could return more than ~50 lines, hit the network, or search a
  repository goes to a subagent. The trigger is output size, not difficulty:
  every tool result is re-billed on every later turn of the session.
- Mark inferred defaults, versions, and interfaces as assumptions, not facts.
  If it is not confirmed in source or docs you actually read, say so.
- Never commit or push unless explicitly asked. Never commit a red tree.
- Before a commit the operator asked for, run the `audit` skill (internal
  auditor plus one external model); code that deletes data, deploys, writes
  live systems or handles secrets gets its two-external variant.
- Never hardcode a secret. Credentials resolve from 1Password `op://`
  references injected per command; a literal value in a tracked file is a leak.
- `git` over HTTPS is already authenticated by a credential helper. `gh` needs
  `opwith git gh ...` if a bare `gh` reports no login. Never run `gh auth
  login` — it writes a plaintext token to disk.
- No emoji in repository files, commit messages, or code comments.
- A result that looks surprisingly good is a bug hypothesis before it is a
  finding. Check for the trivial explanation first, then report both.
